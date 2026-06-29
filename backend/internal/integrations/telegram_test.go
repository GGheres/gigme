package integrations

import (
	"io"
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

// TestTelegramClientCopyMessage verifies copyMessage payload is sent.
func TestTelegramClientCopyMessage(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/bottoken/copyMessage" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		body, err := io.ReadAll(r.Body)
		if err != nil {
			t.Fatalf("read body: %v", err)
		}
		payload := string(body)
		for _, part := range []string{`"chat_id":123`, `"from_chat_id":456`, `"message_id":789`} {
			if !strings.Contains(payload, part) {
				t.Fatalf("expected %q in payload %s", part, payload)
			}
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"ok":true,"result":{"message_id":1}}`))
	}))
	defer server.Close()

	client := &TelegramClient{
		token:   "token",
		client:  server.Client(),
		baseURL: server.URL,
	}

	if err := client.CopyMessage(123, 456, 789, nil); err != nil {
		t.Fatalf("CopyMessage() error = %v", err)
	}
}
