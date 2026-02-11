package tochka

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

type TokenManagerConfig struct {
	ClientID     string
	ClientSecret string
	Scope        string
	TokenURL     string
}

type tokenResponse struct {
	AccessToken string `json:"access_token"`
	TokenType   string `json:"token_type"`
	ExpiresIn   int64  `json:"expires_in"`
}

type TokenManager struct {
	client       *http.Client
	cfg          TokenManagerConfig
	now          func() time.Time
	refreshSkew  time.Duration
	mu           sync.Mutex
	cachedToken  string
	cachedExpiry time.Time
}

func NewTokenManager(cfg TokenManagerConfig, client *http.Client) *TokenManager {
	if client == nil {
		client = &http.Client{Timeout: 10 * time.Second}
	}
	if strings.TrimSpace(cfg.TokenURL) == "" {
		cfg.TokenURL = "https://enter.tochka.com/connect/token"
	}
	return &TokenManager{
		client:      client,
		cfg:         cfg,
		now:         time.Now,
		refreshSkew: 30 * time.Second,
	}
}

func (tm *TokenManager) AccessToken(ctx context.Context) (string, error) {
	tm.mu.Lock()
	defer tm.mu.Unlock()

	now := tm.now()
	if tm.cachedToken != "" && now.Before(tm.cachedExpiry.Add(-tm.refreshSkew)) {
		return tm.cachedToken, nil
	}

	if err := tm.refreshLocked(ctx); err != nil {
		return "", err
	}
	return tm.cachedToken, nil
}

func (tm *TokenManager) refreshLocked(ctx context.Context) error {
	if strings.TrimSpace(tm.cfg.ClientID) == "" || strings.TrimSpace(tm.cfg.ClientSecret) == "" {
		return fmt.Errorf("tochka client credentials are required")
	}

	form := url.Values{}
	form.Set("grant_type", "client_credentials")
	form.Set("client_id", tm.cfg.ClientID)
	form.Set("client_secret", tm.cfg.ClientSecret)
	if strings.TrimSpace(tm.cfg.Scope) != "" {
		form.Set("scope", strings.TrimSpace(tm.cfg.Scope))
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, tm.cfg.TokenURL, strings.NewReader(form.Encode()))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Accept", "application/json")

	resp, err := tm.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("tochka oauth token request failed: status=%d body=%s", resp.StatusCode, strings.TrimSpace(string(body)))
	}

	var parsed tokenResponse
	if err := json.Unmarshal(body, &parsed); err != nil {
		return fmt.Errorf("decode tochka token response: %w", err)
	}
	if strings.TrimSpace(parsed.AccessToken) == "" {
		return fmt.Errorf("tochka oauth token response missing access_token")
	}

	expiresIn := parsed.ExpiresIn
	if expiresIn <= 0 {
		expiresIn = 300
	}
	tm.cachedToken = strings.TrimSpace(parsed.AccessToken)
	tm.cachedExpiry = tm.now().Add(time.Duration(expiresIn) * time.Second)
	return nil
}
