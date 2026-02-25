package handlers

import (
	"encoding/json"
	"net/http"
	"strings"

	"gigme/backend/internal/auth"

	"golang.org/x/crypto/bcrypt"
)

// adminAuthRequest represents admin auth request.
type adminAuthRequest struct {
	Username   string `json:"username"`
	Password   string `json:"password"`
	TelegramID *int64 `json:"telegramId"`
}

// AuthAdmin authenticates admin.
func (h *Handler) AuthAdmin(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	var req adminAuthRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		logger.Warn("action", "action", "auth_admin", "status", "invalid_json")
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	username := strings.TrimSpace(req.Username)
	password := req.Password
	if username == "" || password == "" {
		logger.Warn("action", "action", "auth_admin", "status", "invalid_credentials")
		writeError(w, http.StatusBadRequest, "username and password required")
		return
	}
	if h.cfg.AdminLogin == "" || (h.cfg.AdminPassword == "" && h.cfg.AdminPassHash == "") {
		logger.Warn("action", "action", "auth_admin", "status", "disabled")
		writeError(w, http.StatusUnauthorized, "admin login disabled")
		return
	}
	if username != h.cfg.AdminLogin {
		logger.Warn("action", "action", "auth_admin", "status", "invalid_credentials")
		writeError(w, http.StatusUnauthorized, "invalid credentials")
		return
	}
	if h.cfg.AdminPassHash != "" {
		if err := bcrypt.CompareHashAndPassword([]byte(h.cfg.AdminPassHash), []byte(password)); err != nil {
			logger.Warn("action", "action", "auth_admin", "status", "invalid_credentials")
			writeError(w, http.StatusUnauthorized, "invalid credentials")
			return
		}
	} else if password != h.cfg.AdminPassword {
		logger.Warn("action", "action", "auth_admin", "status", "invalid_credentials")
		writeError(w, http.StatusUnauthorized, "invalid credentials")
		return
	}

	telegramID, ok := h.resolveAdminTelegramID(req.TelegramID)
	if !ok {
		writeError(w, http.StatusBadRequest, "telegramId required")
		return
	}
	if _, allowed := h.cfg.AdminTGIDs[telegramID]; !allowed {
		logger.Warn("action", "action", "auth_admin", "status", "forbidden", "telegram_id", telegramID)
		writeError(w, http.StatusForbidden, "forbidden")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	user, err := h.repo.EnsureUserByTelegramID(ctx, telegramID, username, "Admin", "")
	if err != nil {
		logger.Error("action", "action", "auth_admin", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	_ = h.repo.TouchUserLastSeen(ctx, user.ID)

	token, err := auth.SignAccessToken(h.cfg.JWTSecret, user.ID, user.TelegramID, false, true)
	if err != nil {
		logger.Error("action", "action", "auth_admin", "status", "token_error", "error", err)
		writeError(w, http.StatusInternalServerError, "token error")
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"accessToken": token,
		"user":        user,
		"isNew":       false,
	})
}

// resolveAdminTelegramID handles resolve admin telegram i d.
func (h *Handler) resolveAdminTelegramID(requested *int64) (int64, bool) {
	if requested != nil && *requested > 0 {
		return *requested, true
	}
	if len(h.cfg.AdminTGIDs) == 1 {
		for id := range h.cfg.AdminTGIDs {
			return id, true
		}
	}
	return 0, false
}
