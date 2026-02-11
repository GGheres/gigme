package tochka

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestTokenManagerRefreshesBeforeUse(t *testing.T) {
	t.Parallel()

	callCount := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			t.Fatalf("expected POST, got %s", r.Method)
		}
		if got := r.Header.Get("Content-Type"); got != "application/x-www-form-urlencoded" {
			t.Fatalf("unexpected content-type: %s", got)
		}
		if err := r.ParseForm(); err != nil {
			t.Fatalf("parse form: %v", err)
		}
		if r.Form.Get("grant_type") != "client_credentials" {
			t.Fatalf("unexpected grant_type: %s", r.Form.Get("grant_type"))
		}
		if r.Form.Get("client_id") != "client-id" || r.Form.Get("client_secret") != "client-secret" {
			t.Fatalf("missing credentials in form")
		}
		if r.Form.Get("scope") != "sbp" {
			t.Fatalf("unexpected scope: %s", r.Form.Get("scope"))
		}

		callCount++
		_ = json.NewEncoder(w).Encode(map[string]interface{}{
			"access_token": "token-" + time.Now().Format("150405") + "-" + string(rune('0'+callCount)),
			"token_type":   "bearer",
			"expires_in":   60,
		})
	}))
	defer server.Close()

	tm := NewTokenManager(TokenManagerConfig{
		ClientID:     "client-id",
		ClientSecret: "client-secret",
		Scope:        "sbp",
		TokenURL:     server.URL,
	}, server.Client())

	base := time.Date(2026, 2, 11, 12, 0, 0, 0, time.UTC)
	now := base
	tm.now = func() time.Time { return now }
	tm.refreshSkew = 0

	tok1, err := tm.AccessToken(context.Background())
	if err != nil {
		t.Fatalf("first token: %v", err)
	}
	tok2, err := tm.AccessToken(context.Background())
	if err != nil {
		t.Fatalf("second token: %v", err)
	}
	if tok1 != tok2 {
		t.Fatalf("expected cached token, got %q vs %q", tok1, tok2)
	}
	if callCount != 1 {
		t.Fatalf("expected 1 token request, got %d", callCount)
	}

	now = now.Add(2 * time.Minute)
	tok3, err := tm.AccessToken(context.Background())
	if err != nil {
		t.Fatalf("third token: %v", err)
	}
	if tok3 == tok2 {
		t.Fatalf("expected refreshed token, got same %q", tok3)
	}
	if callCount != 2 {
		t.Fatalf("expected 2 token requests, got %d", callCount)
	}
}
