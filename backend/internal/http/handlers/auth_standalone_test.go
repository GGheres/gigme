package handlers

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strconv"
	"testing"
	"time"

	"gigme/backend/internal/auth"
	"gigme/backend/internal/config"
)

func TestStandaloneAuthExchange(t *testing.T) {
	const botToken = "123456:test_bot_token"
	authDate := time.Now().Unix()

	values := url.Values{}
	values.Set("id", "54321")
	values.Set("first_name", "Alex")
	values.Set("last_name", "Tester")
	values.Set("username", "alex_tester")
	values.Set("photo_url", "https://example.com/u.jpg")
	values.Set("auth_date", strconv.FormatInt(authDate, 10))
	hash := signLoginWidgetPayload(botToken, values)

	body, _ := json.Marshal(map[string]interface{}{
		"id":         54321,
		"first_name": "Alex",
		"last_name":  "Tester",
		"username":   "alex_tester",
		"photo_url":  "https://example.com/u.jpg",
		"auth_date":  authDate,
		"hash":       hash,
	})

	h := New(
		nil,
		nil,
		nil,
		nil,
		&config.Config{
			TelegramToken: botToken,
			TelegramUser:  "gigme_test_bot",
		},
		slog.New(slog.NewTextHandler(io.Discard, nil)),
	)

	req := httptest.NewRequest(http.MethodPost, "/auth/standalone/exchange", bytes.NewReader(body))
	resp := httptest.NewRecorder()
	h.StandaloneAuthExchange(resp, req)

	if resp.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d (%s)", resp.Code, resp.Body.String())
	}

	var payload standaloneAuthExchangeResponse
	if err := json.Unmarshal(resp.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if payload.InitData == "" {
		t.Fatalf("expected non-empty initData")
	}

	user, _, err := auth.ValidateInitData(payload.InitData, botToken, time.Hour)
	if err != nil {
		t.Fatalf("ValidateInitData failed: %v", err)
	}
	if user.ID != 54321 {
		t.Fatalf("unexpected user id: %d", user.ID)
	}
	if user.Username != "alex_tester" {
		t.Fatalf("unexpected username: %s", user.Username)
	}
}

func signLoginWidgetPayload(botToken string, values url.Values) string {
	keys := make([]string, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	// small deterministic sort for test payload keys
	for i := 0; i < len(keys); i++ {
		for j := i + 1; j < len(keys); j++ {
			if keys[j] < keys[i] {
				keys[i], keys[j] = keys[j], keys[i]
			}
		}
	}

	data := ""
	for idx, key := range keys {
		if idx > 0 {
			data += "\n"
		}
		data += key + "=" + values.Get(key)
	}

	secret := sha256.Sum256([]byte(botToken))
	mac := hmac.New(sha256.New, secret[:])
	mac.Write([]byte(data))
	return hex.EncodeToString(mac.Sum(nil))
}
