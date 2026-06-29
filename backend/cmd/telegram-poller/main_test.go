package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

// TestPollOnceForwardsUpdates verifies ordered forwarding and offset advancement.
func TestPollOnceForwardsUpdates(t *testing.T) {
	var forwarded map[string]interface{}
	mux := http.NewServeMux()
	server := httptest.NewServer(mux)
	defer server.Close()

	mux.HandleFunc("/bottest-token/getUpdates", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Query().Get("offset") != "40" {
			t.Fatalf("unexpected offset: %s", r.URL.Query().Get("offset"))
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"ok":true,"result":[{"update_id":41,"message":{"text":"/start"}}]}`))
	})
	mux.HandleFunc("/internal", func(w http.ResponseWriter, r *http.Request) {
		if err := json.NewDecoder(r.Body).Decode(&forwarded); err != nil {
			t.Fatalf("decode forwarded update: %v", err)
		}
		w.WriteHeader(http.StatusOK)
	})

	p := &poller{
		botToken:  "test-token",
		apiBase:   server.URL,
		forwardTo: server.URL + "/internal",
		client:    server.Client(),
	}
	nextOffset, err := p.pollOnce(context.Background(), 40)
	if err != nil {
		t.Fatalf("pollOnce returned error: %v", err)
	}
	if nextOffset != 42 {
		t.Fatalf("next offset = %d, want 42", nextOffset)
	}
	if forwarded["update_id"] != float64(41) {
		t.Fatalf("unexpected forwarded update: %#v", forwarded)
	}
}

// TestDisableWebhookPreservesPendingUpdates verifies safe transition to polling mode.
func TestDisableWebhookPreservesPendingUpdates(t *testing.T) {
	mux := http.NewServeMux()
	server := httptest.NewServer(mux)
	defer server.Close()

	mux.HandleFunc("/bottest-token/deleteWebhook", func(w http.ResponseWriter, r *http.Request) {
		if err := r.ParseForm(); err != nil {
			t.Fatalf("parse form: %v", err)
		}
		if r.Form.Get("drop_pending_updates") != "false" {
			t.Fatalf("pending updates must be preserved")
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"ok":true,"result":true}`))
	})

	p := &poller{
		botToken: "test-token",
		apiBase:  server.URL,
		client:   server.Client(),
	}
	if err := p.disableWebhook(context.Background()); err != nil {
		t.Fatalf("disableWebhook returned error: %v", err)
	}
}
