package tochka

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"path"
	"strings"
	"time"
)

const (
	QRCTypeStatic  = "01"
	QRCTypeDynamic = "02"
)

type Config struct {
	BaseURL      string
	CustomerCode string
}

type Client struct {
	baseURL      string
	customerCode string
	httpClient   *http.Client
	tokens       *TokenManager
	logger       *slog.Logger
}

type APIError struct {
	StatusCode int
	Body       string
}

func (e *APIError) Error() string {
	return fmt.Sprintf("tochka api status %d: %s", e.StatusCode, e.Body)
}

type RegisterQRCodeRequest struct {
	Amount         *int64               `json:"amount,omitempty"`
	Currency       string               `json:"currency,omitempty"`
	PaymentPurpose string               `json:"paymentPurpose"`
	QRCType        string               `json:"qrcType"`
	ImageParams    *QRCodeRequestParams `json:"imageParams,omitempty"`
	SourceName     string               `json:"sourceName,omitempty"`
	TTL            *int                 `json:"ttl,omitempty"`
	RedirectURL    string               `json:"redirectUrl,omitempty"`
}

type QRCodeRequestParams struct {
	Width     int    `json:"width"`
	Height    int    `json:"height"`
	MediaType string `json:"mediaType,omitempty"`
}

type QRCodeContent struct {
	Width     int    `json:"width"`
	Height    int    `json:"height"`
	MediaType string `json:"mediaType"`
	Content   string `json:"content"`
}

type RegisteredQRCode struct {
	Payload string         `json:"payload"`
	QRCID   string         `json:"qrcId"`
	Image   *QRCodeContent `json:"image,omitempty"`
}

type QRCode struct {
	Status            string         `json:"status"`
	Payload           string         `json:"payload"`
	AccountID         string         `json:"accountId"`
	CreatedAt         string         `json:"createdAt"`
	MerchantID        string         `json:"merchantId"`
	LegalID           string         `json:"legalId"`
	QRCID             string         `json:"qrcId"`
	Amount            *int64         `json:"amount,omitempty"`
	TTL               string         `json:"ttl"`
	PaymentPurpose    string         `json:"paymentPurpose"`
	Image             *QRCodeContent `json:"image,omitempty"`
	CommissionPercent float64        `json:"commissionPercent"`
	Currency          string         `json:"currency"`
	QRCType           string         `json:"qrcType"`
	TemplateVersion   string         `json:"templateVersion"`
	SourceName        string         `json:"sourceName"`
}

type QRCodePaymentStatus struct {
	QRCID   string `json:"qrcId"`
	Code    string `json:"code"`
	Status  string `json:"status"`
	Message string `json:"message"`
	TrxID   string `json:"trxId"`
}

type registerQRCodeRequestEnvelope struct {
	Data RegisterQRCodeRequest `json:"Data"`
}

type registerQRCodeResponseEnvelope struct {
	Data RegisteredQRCode `json:"Data"`
}

type getQRCodeResponseEnvelope struct {
	Data QRCode `json:"Data"`
}

type listQRCodesResponseEnvelope struct {
	Data struct {
		QRCodeList []QRCode `json:"qrCodeList"`
	} `json:"Data"`
}

type paymentStatusesResponseEnvelope struct {
	Data struct {
		PaymentList []QRCodePaymentStatus `json:"paymentList"`
	} `json:"Data"`
}

func NewClient(cfg Config, tm *TokenManager, httpClient *http.Client, logger *slog.Logger) *Client {
	if httpClient == nil {
		httpClient = &http.Client{Timeout: 15 * time.Second}
	}
	baseURL := strings.TrimRight(strings.TrimSpace(cfg.BaseURL), "/")
	if baseURL == "" {
		baseURL = "https://enter.tochka.com/uapi"
	}
	return &Client{
		baseURL:      baseURL,
		customerCode: strings.TrimSpace(cfg.CustomerCode),
		httpClient:   httpClient,
		tokens:       tm,
		logger:       logger,
	}
}

func (c *Client) RegisterQRCode(ctx context.Context, merchantID, accountID string, in RegisterQRCodeRequest) (RegisteredQRCode, []byte, error) {
	var out RegisteredQRCode
	pathPart := fmt.Sprintf("/sbp/v1.0/qr-code/merchant/%s/%s", url.PathEscape(strings.TrimSpace(merchantID)), url.PathEscape(strings.TrimSpace(accountID)))
	payload, err := json.Marshal(registerQRCodeRequestEnvelope{Data: in})
	if err != nil {
		return out, nil, err
	}
	body, err := c.do(ctx, http.MethodPost, pathPart, payload)
	if err != nil {
		return out, body, err
	}
	var resp registerQRCodeResponseEnvelope
	if err := json.Unmarshal(body, &resp); err != nil {
		return out, body, fmt.Errorf("decode register qr response: %w", err)
	}
	if strings.TrimSpace(resp.Data.QRCID) == "" || strings.TrimSpace(resp.Data.Payload) == "" {
		return out, body, fmt.Errorf("register qr response missing qrcId or payload")
	}
	return resp.Data, body, nil
}

func (c *Client) GetQRCode(ctx context.Context, qrcID string) (QRCode, []byte, error) {
	var out QRCode
	pathPart := fmt.Sprintf("/sbp/v1.0/qr-code/%s", url.PathEscape(strings.TrimSpace(qrcID)))
	body, err := c.do(ctx, http.MethodGet, pathPart, nil)
	if err != nil {
		return out, body, err
	}
	var resp getQRCodeResponseEnvelope
	if err := json.Unmarshal(body, &resp); err != nil {
		return out, body, fmt.Errorf("decode get qr response: %w", err)
	}
	return resp.Data, body, nil
}

func (c *Client) ListQRCodes(ctx context.Context, legalID string) ([]QRCode, []byte, error) {
	pathPart := fmt.Sprintf("/sbp/v1.0/qr-code/legal-entity/%s", url.PathEscape(strings.TrimSpace(legalID)))
	body, err := c.do(ctx, http.MethodGet, pathPart, nil)
	if err != nil {
		return nil, body, err
	}
	var resp listQRCodesResponseEnvelope
	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, body, fmt.Errorf("decode list qr response: %w", err)
	}
	return resp.Data.QRCodeList, body, nil
}

func (c *Client) GetQRCodesPaymentStatus(ctx context.Context, qrcIDs []string) ([]QRCodePaymentStatus, []byte, error) {
	clean := make([]string, 0, len(qrcIDs))
	for _, id := range qrcIDs {
		trimmed := strings.TrimSpace(id)
		if trimmed == "" {
			continue
		}
		clean = append(clean, trimmed)
	}
	if len(clean) == 0 {
		return nil, nil, fmt.Errorf("qrcIds are required")
	}
	joined := strings.Join(clean, ",")
	pathPart := fmt.Sprintf("/sbp/v1.0/qr-codes/%s/payment-status", url.PathEscape(joined))
	body, err := c.do(ctx, http.MethodGet, pathPart, nil)
	if err != nil {
		return nil, body, err
	}
	var resp paymentStatusesResponseEnvelope
	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, body, fmt.Errorf("decode payment statuses response: %w", err)
	}
	return resp.Data.PaymentList, body, nil
}

func IsPaidStatus(status string) bool {
	return strings.EqualFold(strings.TrimSpace(status), "Accepted")
}

func (c *Client) do(ctx context.Context, method, pathPart string, payload []byte) ([]byte, error) {
	if c.tokens == nil {
		return nil, fmt.Errorf("tochka token manager is required")
	}
	token, err := c.tokens.AccessToken(ctx)
	if err != nil {
		return nil, err
	}

	target := c.baseURL + path.Clean("/"+strings.TrimSpace(pathPart))
	if strings.HasSuffix(pathPart, "/") && !strings.HasSuffix(target, "/") {
		target += "/"
	}

	var bodyReader io.Reader
	if len(payload) > 0 {
		bodyReader = bytes.NewReader(payload)
	}
	req, err := http.NewRequestWithContext(ctx, method, target, bodyReader)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/json")
	req.Header.Set("Authorization", "Bearer "+token)
	if len(payload) > 0 {
		req.Header.Set("Content-Type", "application/json")
	}
	if c.customerCode != "" {
		req.Header.Set("customerCode", c.customerCode)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return body, &APIError{StatusCode: resp.StatusCode, Body: strings.TrimSpace(string(body))}
	}

	if c.logger != nil {
		c.logger.Debug("tochka_api_response", "method", method, "path", pathPart, "status", resp.StatusCode)
	}
	return body, nil
}
