package tochka

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// TestRegisterQRCodeParsing verifies register q r code parsing behavior.
func TestRegisterQRCodeParsing(t *testing.T) {
	t.Parallel()

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/connect/token":
			_ = r.ParseForm()
			_ = json.NewEncoder(w).Encode(map[string]interface{}{
				"access_token": "test-access",
				"token_type":   "bearer",
				"expires_in":   3600,
			})
		case "/uapi/sbp/v1.0/qr-code/merchant/MF0000000001/40817810802000000008/044525104":
			if got := r.Header.Get("Authorization"); got != "Bearer test-access" {
				t.Fatalf("unexpected auth header: %s", got)
			}
			if r.Method != http.MethodPost {
				t.Fatalf("unexpected method: %s", r.Method)
			}
			var raw map[string]interface{}
			if err := json.NewDecoder(r.Body).Decode(&raw); err != nil {
				t.Fatalf("decode request: %v", err)
			}
			data, _ := raw["Data"].(map[string]interface{})
			if data["qrcType"] != "02" {
				t.Fatalf("unexpected qrcType: %#v", data["qrcType"])
			}
			_ = json.NewEncoder(w).Encode(map[string]interface{}{
				"Data": map[string]interface{}{
					"payload": "https://qr.nspk.ru/AS1000670LSS7DN18SJQDNP4B05KLJL2",
					"qrcId":   "AS1000670LSS7DN18SJQDNP4B05KLJL2",
				},
				"Links": map[string]interface{}{"self": "https://example.com"},
				"Meta":  map[string]interface{}{"totalPages": 1},
			})
		default:
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
	}))
	defer srv.Close()

	tm := NewTokenManager(TokenManagerConfig{
		ClientID:     "id",
		ClientSecret: "secret",
		Scope:        "sbp",
		TokenURL:     srv.URL + "/connect/token",
	}, srv.Client())
	tm.now = func() time.Time { return time.Date(2026, 2, 11, 12, 0, 0, 0, time.UTC) }
	tm.refreshSkew = 0

	client := NewClient(Config{BaseURL: srv.URL + "/uapi"}, tm, srv.Client(), nil)
	amount := int64(159900)
	ttl := 15
	resp, raw, err := client.RegisterQRCode(context.Background(), "MF0000000001", "40817810802000000008/044525104", RegisterQRCodeRequest{
		Amount:         &amount,
		Currency:       "RUB",
		PaymentPurpose: "Order test-1",
		QRCType:        QRCTypeDynamic,
		TTL:            &ttl,
	})
	if err != nil {
		t.Fatalf("register qr: %v", err)
	}
	if strings.TrimSpace(resp.Payload) == "" || strings.TrimSpace(resp.QRCID) == "" {
		t.Fatalf("unexpected register response: %#v", resp)
	}
	if !strings.Contains(string(raw), "qrcId") {
		t.Fatalf("raw body should contain qrcId: %s", string(raw))
	}
}

// TestIsPaidStatus verifies is paid status behavior.
func TestIsPaidStatus(t *testing.T) {
	t.Parallel()
	if !IsPaidStatus("Accepted") {
		t.Fatalf("Accepted should be paid")
	}
	if IsPaidStatus("InProgress") {
		t.Fatalf("InProgress should not be paid")
	}
}
