package middleware

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"gigme/backend/internal/auth"
	"gigme/backend/internal/db"
	"gigme/backend/internal/repository"

	"github.com/go-chi/chi/v5"
)

func TestBlockedUserMiddleware(t *testing.T) {
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

	telegramID := int64(999010)
	row := pool.QueryRow(ctx, `INSERT INTO users (telegram_id, username, first_name, last_name, is_blocked)
VALUES ($1, $2, $3, $4, true)
RETURNING id;`, telegramID, "blocked_user", "Blocked", "User")
	var userID int64
	if err := row.Scan(&userID); err != nil {
		t.Fatalf("insert blocked user: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, "DELETE FROM users WHERE id = $1", userID)
	})

	secret := "test-secret"
	token, err := auth.SignAccessToken(secret, userID, telegramID, false, false)
	if err != nil {
		t.Fatalf("token error: %v", err)
	}

	r := chi.NewRouter()
	r.Use(AuthMiddleware(secret))
	r.Use(BlockedUserMiddleware(repo, map[int64]struct{}{}))
	r.Get("/me", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	req := httptest.NewRequest(http.MethodGet, "/me", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	resp := httptest.NewRecorder()
	r.ServeHTTP(resp, req)

	if resp.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", resp.Code)
	}
	if !strings.Contains(resp.Body.String(), "blocked") {
		t.Fatalf("expected blocked response, got %s", resp.Body.String())
	}
}
