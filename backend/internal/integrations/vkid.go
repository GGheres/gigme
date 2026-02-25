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

// VKIDAuthError represents v k i d auth error.
type VKIDAuthError struct {
	Code        string
	Description string
	StatusCode  int
}

// Error handles internal error behavior.
func (e *VKIDAuthError) Error() string {
	if e == nil {
		return "vk id auth error"
	}
	if e.Description == "" {
		return fmt.Sprintf("vk id auth error: %s", e.Code)
	}
	return fmt.Sprintf("vk id auth error: %s (%s)", e.Code, e.Description)
}

// VKIDToken represents v k i d token.
type VKIDToken struct {
	AccessToken  string
	RefreshToken string
	IDToken      string
	ExpiresIn    int64
	UserID       int64
	Scope        string
}

// VKIDUserInfo represents v k i d user info.
type VKIDUserInfo struct {
	UserID    int64
	FirstName string
	LastName  string
	Avatar    string
	Email     string
	Phone     string
}

// VKIDClient represents v k i d client.
type VKIDClient struct {
	client  *http.Client
	baseURL string
	appID   string
}

// NewVKIDClient creates v k i d client.
func NewVKIDClient(appID string) *VKIDClient {
	return &VKIDClient{
		client:  &http.Client{Timeout: 10 * time.Second},
		baseURL: defaultVKIDBaseURL,
		appID:   strings.TrimSpace(appID),
	}
}

// ExchangeCode handles exchange code.
func (c *VKIDClient) ExchangeCode(
	ctx context.Context,
	code string,
	codeVerifier string,
	deviceID string,
	redirectURI string,
	state string,
) (VKIDToken, error) {
	client, endpoint, appID, err := c.resolveAuthRequest("/oauth2/auth")
	if err != nil {
		return VKIDToken{}, err
	}

	query := url.Values{}
	query.Set("grant_type", "authorization_code")
	query.Set("client_id", appID)
	query.Set("code_verifier", strings.TrimSpace(codeVerifier))
	query.Set("device_id", strings.TrimSpace(deviceID))
	query.Set("redirect_uri", strings.TrimSpace(redirectURI))
	query.Set("state", strings.TrimSpace(state))

	body := url.Values{}
	body.Set("code", strings.TrimSpace(code))

	if body.Get("code") == "" ||
		query.Get("code_verifier") == "" ||
		query.Get("device_id") == "" ||
		query.Get("redirect_uri") == "" ||
		query.Get("state") == "" {
		return VKIDToken{}, fmt.Errorf("vk id exchange params are invalid")
	}

	endpoint, err = withQueryParams(endpoint, query)
	if err != nil {
		return VKIDToken{}, err
	}

	payload, err := postVKIDForm(ctx, client, endpoint, body)
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

// GetUserInfo returns user info.
func (c *VKIDClient) GetUserInfo(ctx context.Context, accessToken string) (VKIDUserInfo, error) {
	client, endpoint, appID, err := c.resolveAuthRequest("/oauth2/user_info")
	if err != nil {
		return VKIDUserInfo{}, err
	}

	query := url.Values{}
	query.Set("client_id", appID)

	body := url.Values{}
	body.Set("access_token", strings.TrimSpace(accessToken))
	if body.Get("access_token") == "" {
		return VKIDUserInfo{}, fmt.Errorf("vk id access token is empty")
	}

	endpoint, err = withQueryParams(endpoint, query)
	if err != nil {
		return VKIDUserInfo{}, err
	}

	payload, err := postVKIDForm(ctx, client, endpoint, body)
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

// resolveAuthRequest handles resolve auth request.
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

// postVKIDForm handles post v k i d form.
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

// withQueryParams configures query params.
func withQueryParams(endpoint string, params url.Values) (string, error) {
	parsed, err := url.Parse(endpoint)
	if err != nil {
		return "", fmt.Errorf("invalid vk id endpoint: %w", err)
	}

	query := parsed.Query()
	for key, values := range params {
		for _, value := range values {
			query.Set(key, value)
		}
	}
	parsed.RawQuery = query.Encode()
	return parsed.String(), nil
}

// parseVKIDUserID parses v k i d user i d.
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
