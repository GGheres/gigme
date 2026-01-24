package middleware

import (
	"context"
	"net/http"
	"strings"

	"gigme/backend/internal/auth"
)

type contextKey string

const (
	userIDKey     contextKey = "user_id"
	telegramIDKey contextKey = "telegram_id"
)

func UserIDFromContext(ctx context.Context) (int64, bool) {
	val, ok := ctx.Value(userIDKey).(int64)
	return val, ok
}

func TelegramIDFromContext(ctx context.Context) (int64, bool) {
	val, ok := ctx.Value(telegramIDKey).(int64)
	return val, ok
}

func AuthMiddleware(secret string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			authHeader := r.Header.Get("Authorization")
			if authHeader == "" {
				http.Error(w, "missing Authorization", http.StatusUnauthorized)
				return
			}
			parts := strings.SplitN(authHeader, " ", 2)
			if len(parts) != 2 || strings.ToLower(parts[0]) != "bearer" {
				http.Error(w, "invalid Authorization", http.StatusUnauthorized)
				return
			}
			claims, err := auth.ParseAccessToken(secret, parts[1])
			if err != nil {
				http.Error(w, "invalid token", http.StatusUnauthorized)
				return
			}
			ctx := context.WithValue(r.Context(), userIDKey, claims.UserID)
			ctx = context.WithValue(ctx, telegramIDKey, claims.TelegramID)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}
