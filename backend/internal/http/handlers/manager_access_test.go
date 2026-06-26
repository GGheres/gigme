package handlers

import (
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"gigme/backend/internal/adminaccess"
	"gigme/backend/internal/auth"
	"gigme/backend/internal/config"
	"gigme/backend/internal/http/middleware"
)

// TestRequireAdminPermissionAllowsRuntimeManagerAccess verifies runtime manager grants unlock admin endpoints.
func TestRequireAdminPermissionAllowsRuntimeManagerAccess(t *testing.T) {
	cfg := &config.Config{JWTSecret: "test-secret"}
	handler := New(
		nil,
		nil,
		nil,
		nil,
		cfg,
		slog.New(slog.NewTextHandler(io.Discard, nil)),
	)
	handler.grantTelegramManagerAccess(555001)

	token, err := auth.SignAccessToken(cfg.JWTSecret, 77, 555001, false, false)
	if err != nil {
		t.Fatalf("sign token: %v", err)
	}

	req := httptest.NewRequest(http.MethodGet, "/admin/transfers/orders", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	resp := httptest.NewRecorder()

	middleware.AuthMiddleware(cfg.JWTSecret)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if _, ok := handler.requireAdminPermission(
			handler.loggerForRequest(r),
			w,
			r,
			"admin_list_transfer_orders",
			adminaccess.PermissionTransfers,
		); !ok {
			return
		}
		w.WriteHeader(http.StatusNoContent)
	})).ServeHTTP(resp, req)

	if resp.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d (%s)", resp.Code, resp.Body.String())
	}
}

// TestRequireAdminPermissionDeniesWithoutRuntimeManagerAccess verifies normal user tokens stay blocked.
func TestRequireAdminPermissionDeniesWithoutRuntimeManagerAccess(t *testing.T) {
	cfg := &config.Config{JWTSecret: "test-secret"}
	handler := New(
		nil,
		nil,
		nil,
		nil,
		cfg,
		slog.New(slog.NewTextHandler(io.Discard, nil)),
	)

	token, err := auth.SignAccessToken(cfg.JWTSecret, 78, 555002, false, false)
	if err != nil {
		t.Fatalf("sign token: %v", err)
	}

	req := httptest.NewRequest(http.MethodGet, "/admin/transfers/orders", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	resp := httptest.NewRecorder()

	middleware.AuthMiddleware(cfg.JWTSecret)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if _, ok := handler.requireAdminPermission(
			handler.loggerForRequest(r),
			w,
			r,
			"admin_list_transfer_orders",
			adminaccess.PermissionTransfers,
		); !ok {
			return
		}
		w.WriteHeader(http.StatusNoContent)
	})).ServeHTTP(resp, req)

	if resp.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d (%s)", resp.Code, resp.Body.String())
	}
}
