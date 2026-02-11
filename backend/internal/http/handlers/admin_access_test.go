package handlers

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"gigme/backend/internal/auth"
	"gigme/backend/internal/config"
	"gigme/backend/internal/db"
	"gigme/backend/internal/http/middleware"
	"gigme/backend/internal/repository"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

func TestAdminEndpointsRequireAllowlist(t *testing.T) {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		t.Skip("DATABASE_URL not set")
	}

	ctx := context.Background()
	pool, err := db.NewPool(ctx, dsn)
	if err != nil {
		t.Fatalf("db connection failed: %v", err)
	}
	defer pool.Close()

	repo := repository.New(pool)

	adminTelegramID := int64(999001)
	adminUserID, err := insertTestUser(ctx, pool, adminTelegramID, "admin")
	if err != nil {
		t.Fatalf("insert admin user: %v", err)
	}
	normalTelegramID := int64(999002)
	normalUserID, err := insertTestUser(ctx, pool, normalTelegramID, "user")
	if err != nil {
		t.Fatalf("insert normal user: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, "DELETE FROM users WHERE id = $1", adminUserID)
		_, _ = pool.Exec(ctx, "DELETE FROM users WHERE id = $1", normalUserID)
	})

	cfg := &config.Config{
		JWTSecret:  "test-secret",
		AdminTGIDs: map[int64]struct{}{adminTelegramID: {}},
	}
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	handler := New(repo, nil, nil, cfg, logger)

	r := chi.NewRouter()
	r.Use(middleware.AuthMiddleware(cfg.JWTSecret))
	r.Use(middleware.BlockedUserMiddleware(repo, cfg.AdminTGIDs))
	r.Get("/admin/users", handler.ListAdminUsers)

	adminToken, err := auth.SignAccessToken(cfg.JWTSecret, adminUserID, adminTelegramID, false, true)
	if err != nil {
		t.Fatalf("admin token: %v", err)
	}
	normalToken, err := auth.SignAccessToken(cfg.JWTSecret, normalUserID, normalTelegramID, false, false)
	if err != nil {
		t.Fatalf("user token: %v", err)
	}

	req := httptest.NewRequest(http.MethodGet, "/admin/users", nil)
	req.Header.Set("Authorization", "Bearer "+normalToken)
	resp := httptest.NewRecorder()
	r.ServeHTTP(resp, req)
	if resp.Code != http.StatusForbidden {
		t.Fatalf("expected 403 for non-admin, got %d", resp.Code)
	}

	req = httptest.NewRequest(http.MethodGet, "/admin/users", nil)
	req.Header.Set("Authorization", "Bearer "+adminToken)
	resp = httptest.NewRecorder()
	r.ServeHTTP(resp, req)
	if resp.Code != http.StatusOK {
		t.Fatalf("expected 200 for admin, got %d", resp.Code)
	}
}

func insertTestUser(ctx context.Context, pool *pgxpool.Pool, telegramID int64, suffix string) (int64, error) {
	row := pool.QueryRow(ctx, `INSERT INTO users (telegram_id, username, first_name, last_name)
VALUES ($1, $2, $3, $4)
RETURNING id;`, telegramID, "test_"+suffix, "Test", "User")
	var id int64
	if err := row.Scan(&id); err != nil {
		return 0, err
	}
	return id, nil
}
