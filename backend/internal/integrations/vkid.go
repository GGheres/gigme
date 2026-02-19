package integrations

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

const defaultVKIDBaseURL = "https://id.vk.ru"

type VKIDAuthError struct {
	Code        string
	Description string
	StatusCode  int
}

func (e *VKIDAuthError) Error() string {
	if e == nil {
		return "vk id auth error"
	}
	if e.Description == "" {
		return fmt.Sprintf("vk id auth error: %s", e.Code)
	}
	return fmt.Sprintf("vk id auth error: %s (%s)", e.Code, e.Description)
}

type VKIDToken struct {
	AccessToken  string
	RefreshToken string
	IDToken      string
	ExpiresIn    int64
	UserID       int64
	Scope        string
}

type VKIDUserInfo struct {
	UserID    int64
	FirstName string
	LastName  string
	Avatar    string
	Email     string
	Phone     string
}

type VKIDClient struct {
	client  *http.Client
	baseURL string
	appID   string
}

func NewVKIDClient(appID string) *VKIDClient {
	return &VKIDClient{
		client:  &http.Client{Timeout: 10 * time.Second},
		baseURL: defaultVKIDBaseURL,
		appID:   strings.TrimSpace(appID),
	}
}

func (c *VKIDClient) ExchangeCode(
	ctx context.Context,
	code string,
	codeVerifier string,
	deviceID string,
	redirectURI string,
) (VKIDToken, error) {
	client, endpoint, appID, err := c.resolveAuthRequest("/oauth2/auth")
	if err != nil {
		return VKIDToken{}, err
	}

	values := url.Values{}
	values.Set("grant_type", "authorization_code")
	values.Set("client_id", appID)
	values.Set("code", strings.TrimSpace(code))
	values.Set("code_verifier", strings.TrimSpace(codeVerifier))
	values.Set("device_id", strings.TrimSpace(deviceID))
	values.Set("redirect_uri", strings.TrimSpace(redirectURI))

	if values.Get("code") == "" ||
		values.Get("code_verifier") == "" ||
		values.Get("device_id") == "" ||
		values.Get("redirect_uri") == "" {
		return VKIDToken{}, fmt.Errorf("vk id exchange params are invalid")
	}

	payload, err := postVKIDForm(ctx, client, endpoint, values)
	if err != nil {
		return VKIDToken{}, err
	}

	var response struct {
		AccessToken  string          `json:"access_token"`
		RefreshToken string          `json:"refresh_token"`
		IDToken      string          `json:"id_token"`
		ExpiresIn    int64           `json:"expires_in"`
		UserID       json.RawMessage `json:"user_id"`
		Scope        string          `json:"scope"`
	}
	if err := json.Unmarshal(payload, &response); err != nil {
		return VKIDToken{}, fmt.Errorf("vk id exchange decode failed: %w", err)
	}

	userID, err := parseVKIDUserID(response.UserID)
	if err != nil {
		return VKIDToken{}, fmt.Errorf("vk id exchange user id parse failed: %w", err)
	}
	if strings.TrimSpace(response.AccessToken) == "" {
		return VKIDToken{}, fmt.Errorf("vk id exchange missing access token")
	}

	return VKIDToken{
		AccessToken:  strings.TrimSpace(response.AccessToken),
		RefreshToken: strings.TrimSpace(response.RefreshToken),
		IDToken:      strings.TrimSpace(response.IDToken),
		ExpiresIn:    response.ExpiresIn,
		UserID:       userID,
		Scope:        strings.TrimSpace(response.Scope),
	}, nil
}

func (c *VKIDClient) GetUserInfo(ctx context.Context, accessToken string) (VKIDUserInfo, error) {
	client, endpoint, _, err := c.resolveAuthRequest("/oauth2/user_info")
	if err != nil {
		return VKIDUserInfo{}, err
	}

	values := url.Values{}
	values.Set("access_token", strings.TrimSpace(accessToken))
	if values.Get("access_token") == "" {
		return VKIDUserInfo{}, fmt.Errorf("vk id access token is empty")
	}

	payload, err := postVKIDForm(ctx, client, endpoint, values)
	if err != nil {
		return VKIDUserInfo{}, err
	}

	var response struct {
		User struct {
			UserID    json.RawMessage `json:"user_id"`
			FirstName string          `json:"first_name"`
			LastName  string          `json:"last_name"`
			Avatar    string          `json:"avatar"`
			Email     string          `json:"email"`
			Phone     string          `json:"phone"`
		} `json:"user"`
	}
	if err := json.Unmarshal(payload, &response); err != nil {
		return VKIDUserInfo{}, fmt.Errorf("vk id user_info decode failed: %w", err)
	}

	userID, err := parseVKIDUserID(response.User.UserID)
	if err != nil {
		return VKIDUserInfo{}, fmt.Errorf("vk id user_info user id parse failed: %w", err)
	}

	return VKIDUserInfo{
		UserID:    userID,
		FirstName: strings.TrimSpace(response.User.FirstName),
		LastName:  strings.TrimSpace(response.User.LastName),
		Avatar:    strings.TrimSpace(response.User.Avatar),
		Email:     strings.TrimSpace(response.User.Email),
		Phone:     strings.TrimSpace(response.User.Phone),
	}, nil
}

func (c *VKIDClient) resolveAuthRequest(path string) (*http.Client, string, string, error) {
	if c == nil {
		return nil, "", "", fmt.Errorf("vk id client is nil")
	}
	if strings.TrimSpace(c.appID) == "" {
		return nil, "", "", fmt.Errorf("vk id app id is empty")
	}

	client := c.client
	if client == nil {
		client = http.DefaultClient
	}

	base := strings.TrimSpace(c.baseURL)
	if base == "" {
		base = defaultVKIDBaseURL
	}
	baseURL, err := url.Parse(base)
	if err != nil {
		return nil, "", "", fmt.Errorf("invalid vk id base url: %w", err)
	}
	endpoint := baseURL.ResolveReference(&url.URL{Path: path})
	return client, endpoint.String(), strings.TrimSpace(c.appID), nil
}

func postVKIDForm(
	ctx context.Context,
	client *http.Client,
	endpoint string,
	values url.Values,
) ([]byte, error) {
	req, err := http.NewRequestWithContext(
		ctx,
		http.MethodPost,
		endpoint,
		strings.NewReader(values.Encode()),
	)
	if err != nil {
		return nil, fmt.Errorf("vk id request build failed: %w", err)
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("vk id request failed: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(io.LimitReader(resp.Body, 2<<20))
	if err != nil {
		return nil, fmt.Errorf("vk id response read failed: %w", err)
	}

	var errorPayload struct {
		Error            string `json:"error"`
		ErrorDescription string `json:"error_description"`
	}
	_ = json.Unmarshal(body, &errorPayload)

	if resp.StatusCode >= 300 || strings.TrimSpace(errorPayload.Error) != "" {
		return nil, &VKIDAuthError{
			Code:        strings.TrimSpace(errorPayload.Error),
			Description: strings.TrimSpace(errorPayload.ErrorDescription),
			StatusCode:  resp.StatusCode,
		}
	}

	return body, nil
}

func parseVKIDUserID(raw json.RawMessage) (int64, error) {
	if len(raw) == 0 {
		return 0, fmt.Errorf("empty user_id")
	}

	var asString string
	if err := json.Unmarshal(raw, &asString); err == nil {
		trimmed := strings.TrimSpace(asString)
		if trimmed == "" {
			return 0, fmt.Errorf("empty user_id")
		}
		parsed, err := strconv.ParseInt(trimmed, 10, 64)
		if err != nil || parsed <= 0 {
			return 0, fmt.Errorf("invalid user_id: %q", trimmed)
		}
		return parsed, nil
	}

	var asInt int64
	if err := json.Unmarshal(raw, &asInt); err == nil {
		if asInt <= 0 {
			return 0, fmt.Errorf("invalid user_id: %d", asInt)
		}
		return asInt, nil
	}

	var asFloat float64
	if err := json.Unmarshal(raw, &asFloat); err == nil {
		asInt = int64(asFloat)
		if asInt <= 0 {
			return 0, fmt.Errorf("invalid user_id: %f", asFloat)
		}
		return asInt, nil
	}

	return 0, fmt.Errorf("unsupported user_id format")
}
