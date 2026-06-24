package integrations

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// TestTelegramClientIncludesErrorResponseBody verifies Bot API body is preserved.
func TestTelegramClientIncludesErrorResponseBody(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/bottoken/sendMessage" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		w.WriteHeader(http.StatusForbidden)
		_, _ = w.Write([]byte(`{"ok":false,"description":"Forbidden: bot was blocked by the user"}`))
	}))
	defer server.Close()

	client := &TelegramClient{
		token:   "token",
		client:  server.Client(),
		baseURL: server.URL,
	}

	err := client.SendMessage(123, "hello")
	if err == nil {
		t.Fatal("expected error")
	}
	got := err.Error()
	if !strings.Contains(got, "telegram sendMessage status 403") {
		t.Fatalf("expected status in error, got %q", got)
	}
	if !strings.Contains(got, "Forbidden: bot was blocked by the user") {
		t.Fatalf("expected response body in error, got %q", got)
	}
}
