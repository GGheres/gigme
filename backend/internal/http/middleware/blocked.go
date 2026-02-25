package middleware

import (
	"encoding/json"
	"net/http"

	"gigme/backend/internal/repository"
)

// BlockedUserMiddleware handles blocked user middleware.
func BlockedUserMiddleware(repo *repository.Repository, adminTGIDs map[int64]struct{}) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if repo == nil {
				next.ServeHTTP(w, r)
				return
			}
			telegramID, hasTelegram := TelegramIDFromContext(r.Context())
			if isAdmin, ok := IsAdminFromContext(r.Context()); ok && isAdmin {
				next.ServeHTTP(w, r)
				return
			}
			if hasTelegram {
				if _, allowed := adminTGIDs[telegramID]; allowed {
					next.ServeHTTP(w, r)
					return
				}
			}
			userID, ok := UserIDFromContext(r.Context())
			if !ok {
				next.ServeHTTP(w, r)
				return
			}
			blocked, err := repo.IsUserBlocked(r.Context(), userID)
			if err != nil {
				w.WriteHeader(http.StatusInternalServerError)
				return
			}
			if blocked {
				writeBlocked(w)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// writeBlocked writes blocked.
func writeBlocked(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusForbidden)
	_ = json.NewEncoder(w).Encode(map[string]string{
		"error":   "blocked",
		"message": "Ваш аккаунт заблокирован",
	})
}
