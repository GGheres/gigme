package tests

import (
	"context"
	"errors"
	"testing"

	"gigme/backend/internal/eventparser/core"
)

// TestInstagramAndVKReturnTypedErrorsWhenBlocked verifies instagram and v k return typed errors when blocked behavior.
func TestInstagramAndVKReturnTypedErrorsWhenBlocked(t *testing.T) {
	fetcher := &fakeFetcher{responses: map[string]fakeResponse{
		"https://instagram.com/p/blocked": {
			status: 200,
			body:   []byte(`<html><body>Please log in to continue</body></html>`),
		},
		"https://vk.com/blocked": {
			status: 403,
			body:   []byte(`<html><body>login.vk.com</body></html>`),
		},
	}}
	d := newTestDispatcher(fetcher)

	_, err := d.ParseEvent(context.Background(), "https://instagram.com/p/blocked")
	if err == nil {
		t.Fatalf("expected instagram auth error")
	}
	var authErr *core.AuthRequiredError
	if !errors.As(err, &authErr) {
		t.Fatalf("expected AuthRequiredError for instagram, got %T", err)
	}

	_, err = d.ParseEvent(context.Background(), "https://vk.com/blocked")
	if err == nil {
		t.Fatalf("expected vk auth error")
	}
	authErr = nil
	if !errors.As(err, &authErr) {
		t.Fatalf("expected AuthRequiredError for vk, got %T", err)
	}
}
