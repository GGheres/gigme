package integrations

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const (
	defaultVKAPIBaseURL = "https://api.vk.com"
	defaultVKAPIVersion = "5.199"
)

type VKAuthError struct {
	Code    int
	Message string
}

func (e *VKAuthError) Error() string {
	if e == nil {
		return "vk auth error"
	}
	if e.Code <= 0 {
		return fmt.Sprintf("vk auth error: %s", strings.TrimSpace(e.Message))
	}
	return fmt.Sprintf("vk auth error %d: %s", e.Code, strings.TrimSpace(e.Message))
}

type VKUser struct {
	ID         int64
	FirstName  string
	LastName   string
	ScreenName string
	PhotoURL   string
}

type VKClient struct {
	client  *http.Client
	baseURL string
	version string
}

func NewVKClient() *VKClient {
	return &VKClient{
		client: &http.Client{Timeout: 10 * time.Second},
	}
}

func (c *VKClient) GetUser(ctx context.Context, accessToken string) (VKUser, error) {
	token := strings.TrimSpace(accessToken)
	if token == "" {
		return VKUser{}, fmt.Errorf("vk access token is empty")
	}

	baseURL := defaultVKAPIBaseURL
	version := defaultVKAPIVersion
	client := http.DefaultClient
	if c != nil {
		if c.client != nil {
			client = c.client
		}
		if strings.TrimSpace(c.baseURL) != "" {
			baseURL = strings.TrimSpace(c.baseURL)
		}
		if strings.TrimSpace(c.version) != "" {
			version = strings.TrimSpace(c.version)
		}
	}

	endpoint, err := url.Parse(baseURL)
	if err != nil {
		return VKUser{}, fmt.Errorf("invalid vk base url: %w", err)
	}
	endpoint = endpoint.ResolveReference(&url.URL{Path: "/method/users.get"})

	query := endpoint.Query()
	query.Set("access_token", token)
	query.Set("fields", "photo_200,screen_name")
	query.Set("v", version)
	endpoint.RawQuery = query.Encode()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint.String(), nil)
	if err != nil {
		return VKUser{}, fmt.Errorf("vk request build failed: %w", err)
	}

	resp, err := client.Do(req)
	if err != nil {
		return VKUser{}, fmt.Errorf("vk request failed: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return VKUser{}, fmt.Errorf("vk response read failed: %w", err)
	}

	if resp.StatusCode >= 300 {
		return VKUser{}, fmt.Errorf("vk users.get status %d", resp.StatusCode)
	}

	var payload struct {
		Response []struct {
			ID         int64  `json:"id"`
			FirstName  string `json:"first_name"`
			LastName   string `json:"last_name"`
			ScreenName string `json:"screen_name"`
			Photo200   string `json:"photo_200"`
		} `json:"response"`
		Error *struct {
			Code    int    `json:"error_code"`
			Message string `json:"error_msg"`
		} `json:"error"`
	}

	if err := json.Unmarshal(body, &payload); err != nil {
		return VKUser{}, fmt.Errorf("vk response decode failed: %w", err)
	}

	if payload.Error != nil {
		return VKUser{}, &VKAuthError{
			Code:    payload.Error.Code,
			Message: payload.Error.Message,
		}
	}

	if len(payload.Response) == 0 {
		return VKUser{}, fmt.Errorf("vk users.get empty response")
	}

	user := payload.Response[0]
	if user.ID <= 0 {
		return VKUser{}, fmt.Errorf("vk users.get invalid user id")
	}

	return VKUser{
		ID:         user.ID,
		FirstName:  strings.TrimSpace(user.FirstName),
		LastName:   strings.TrimSpace(user.LastName),
		ScreenName: strings.TrimSpace(user.ScreenName),
		PhotoURL:   strings.TrimSpace(user.Photo200),
	}, nil
}
