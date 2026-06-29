package handlers

import (
	"encoding/json"
	"net/http"
	"strings"

	"gigme/backend/internal/adminaccess"
	"gigme/backend/internal/auth"
)

// adminAuthRequest represents admin auth request.
type adminAuthRequest struct {
	Username   string `json:"username"`
	Password   string `json:"password"`
	TelegramID *int64 `json:"telegramId"`
}

// managerAuthRequest represents password-only manager auth request.
type managerAuthRequest struct {
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
	if h.adminAccess == nil || !h.adminAccess.HasAccounts() {
		logger.Warn("action", "action", "auth_admin", "status", "disabled")
		writeError(w, http.StatusUnauthorized, "admin login disabled")
		return
	}
	account, ok := h.adminAccess.Authenticate(username, password)
	if !ok {
		logger.Warn("action", "action", "auth_admin", "status", "invalid_credentials")
		writeError(w, http.StatusUnauthorized, "invalid credentials")
		return
	}
	telegramID, ok := h.adminAccess.ResolveTelegramID(account, req.TelegramID)
	if !ok {
		writeError(w, http.StatusBadRequest, "telegramId required")
		return
	}

	h.writeAdminSession(w, r, account, telegramID, username, "auth_admin")
}

// AuthManager authenticates the Android manager app with a password-only flow.
func (h *Handler) AuthManager(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	var req managerAuthRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		logger.Warn("action", "action", "auth_manager", "status", "invalid_json")
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	password := req.Password
	if strings.TrimSpace(password) == "" {
		logger.Warn("action", "action", "auth_manager", "status", "invalid_credentials")
		writeError(w, http.StatusBadRequest, "password required")
		return
	}
	if h.cfg == nil || h.adminAccess == nil || !h.adminAccess.HasAccounts() {
		logger.Warn("action", "action", "auth_manager", "status", "disabled")
		writeError(w, http.StatusUnauthorized, "manager login disabled")
		return
	}

	managerLogin := strings.TrimSpace(h.cfg.ManagerLogin)
	if managerLogin == "" {
		logger.Warn("action", "action", "auth_manager", "status", "disabled")
		writeError(w, http.StatusUnauthorized, "manager login disabled")
		return
	}

	account, ok := h.adminAccess.Authenticate(managerLogin, password)
	if !ok || !adminaccess.HasAnyPermission(
		account.Permissions,
		adminaccess.PermissionOrders,
		adminaccess.PermissionTransfers,
		adminaccess.PermissionScanner,
	) {
		logger.Warn("action", "action", "auth_manager", "status", "invalid_credentials")
		writeError(w, http.StatusUnauthorized, "invalid credentials")
		return
	}
	telegramID, ok := h.adminAccess.ResolveTelegramID(account, req.TelegramID)
	if !ok {
		logger.Warn("action", "action", "auth_manager", "status", "telegram_id_required")
		writeError(w, http.StatusBadRequest, "telegramId required")
		return
	}

	h.writeAdminSession(w, r, account, telegramID, managerLogin, "auth_manager")
}

// writeAdminSession persists the synthetic or real admin user and returns a signed scoped session.
func (h *Handler) writeAdminSession(
	w http.ResponseWriter,
	r *http.Request,
	account adminaccess.Account,
	telegramID int64,
	username string,
	action string,
) {
	logger := h.loggerForRequest(r)
	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	user, err := h.repo.EnsureUserByTelegramID(ctx, telegramID, username, username, "")
	if err != nil {
		logger.Error("action", "action", action, "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	_ = h.repo.TouchUserLastSeen(ctx, user.ID)

	var token string
	if action == "auth_manager" {
		token, err = auth.SignManagerAccessTokenWithAdminPermissions(
			h.cfg.JWTSecret,
			user.ID,
			user.TelegramID,
			account.Permissions,
		)
	} else {
		token, err = auth.SignAccessTokenWithAdminPermissions(
			h.cfg.JWTSecret,
			user.ID,
			user.TelegramID,
			false,
			true,
			account.Permissions,
		)
	}
	if err != nil {
		logger.Error("action", "action", action, "status", "token_error", "error", err)
		writeError(w, http.StatusInternalServerError, "token error")
		return
	}
	user.AdminPermissions = append([]string(nil), account.Permissions...)

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"accessToken": token,
		"user":        user,
		"isNew":       false,
	})
}
