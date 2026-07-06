package handlers

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"gigme/backend/internal/repository"
)

// TestHandleTicketingErrorTransferProductAlreadyExists verifies duplicate transfer product conflicts.
func TestHandleTicketingErrorTransferProductAlreadyExists(t *testing.T) {
	t.Parallel()

	handler := Handler{}
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	resp := httptest.NewRecorder()

	handler.handleTicketingError(
		logger,
		resp,
		"admin_create_transfer_product",
		repository.ErrTransferProductAlreadyExists,
	)

	if resp.Code != http.StatusConflict {
		t.Fatalf("status = %d, want %d", resp.Code, http.StatusConflict)
	}

	var body map[string]string
	if err := json.Unmarshal(resp.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if body["error"] != repository.ErrTransferProductAlreadyExists.Error() {
		t.Fatalf("error = %q, want %q", body["error"], repository.ErrTransferProductAlreadyExists.Error())
	}
}
