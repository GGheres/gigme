package handlers

import (
	"net/http"
	"strings"
	"time"

	"gigme/backend/internal/adminaccess"
	"gigme/backend/internal/http/middleware"
)

const managerPasswordPromptTTL = 5 * time.Minute

// effectiveAdminPermissionsForTelegramID resolves all admin permissions for the Telegram account.
func (h *Handler) effectiveAdminPermissionsForTelegramID(telegramID int64) []string {
	if h == nil || telegramID == 0 {
		return nil
	}

	permissions := make([]string, 0, 4)
	if h.adminAccess != nil {
		permissions = mergeAdminPermissions(
			permissions,
			h.adminAccess.PermissionsForTelegramID(telegramID),
		)
	}
	if h.hasTelegramManagerAccess(telegramID) {
		permissions = mergeAdminPermissions(
			permissions,
			adminaccess.ManagerPermissions(),
		)
	}
	return permissions
}

// currentAdminPermissions returns permissions from the token and runtime manager grants.
func (h *Handler) currentAdminPermissions(r *http.Request, telegramID int64) []string {
	if telegramID == 0 {
		return nil
	}

	permissions := make([]string, 0, 4)
	if r != nil {
		if tokenPermissions, ok := middleware.AdminPermissionsFromContext(r.Context()); ok {
			permissions = mergeAdminPermissions(permissions, tokenPermissions)
		}
	}

	return mergeAdminPermissions(
		permissions,
		h.effectiveAdminPermissionsForTelegramID(telegramID),
	)
}

// promptTelegramManagerPassword marks the Telegram account as waiting for the manager password.
func (h *Handler) promptTelegramManagerPassword(telegramID int64) {
	if h == nil || telegramID <= 0 {
		return
	}
	h.managerAccessMu.Lock()
	defer h.managerAccessMu.Unlock()
	h.managerPrompts[telegramID] = time.Now().Add(managerPasswordPromptTTL)
}

// clearTelegramManagerPrompt clears the pending manager-password prompt for the Telegram account.
func (h *Handler) clearTelegramManagerPrompt(telegramID int64) {
	if h == nil || telegramID <= 0 {
		return
	}
	h.managerAccessMu.Lock()
	defer h.managerAccessMu.Unlock()
	delete(h.managerPrompts, telegramID)
}

// isAwaitingTelegramManagerPassword reports whether the account is inside the password prompt window.
func (h *Handler) isAwaitingTelegramManagerPassword(telegramID int64) bool {
	if h == nil || telegramID <= 0 {
		return false
	}

	h.managerAccessMu.Lock()
	defer h.managerAccessMu.Unlock()

	deadline, ok := h.managerPrompts[telegramID]
	if !ok {
		return false
	}
	if time.Now().After(deadline) {
		delete(h.managerPrompts, telegramID)
		return false
	}
	return true
}

// grantTelegramManagerAccess enables runtime manager permissions for the Telegram account.
func (h *Handler) grantTelegramManagerAccess(telegramID int64) {
	if h == nil || telegramID <= 0 {
		return
	}
	h.managerAccessMu.Lock()
	defer h.managerAccessMu.Unlock()
	h.managerSessions[telegramID] = time.Now()
}

// hasTelegramManagerAccess reports whether runtime manager access is active for the account.
func (h *Handler) hasTelegramManagerAccess(telegramID int64) bool {
	if h == nil || telegramID <= 0 {
		return false
	}
	h.managerAccessMu.RLock()
	defer h.managerAccessMu.RUnlock()
	_, ok := h.managerSessions[telegramID]
	return ok
}

// authenticateTelegramManagerPassword validates the configured manager password for bot activation.
func (h *Handler) authenticateTelegramManagerPassword(password string) bool {
	if h == nil || h.adminAccess == nil || h.cfg == nil {
		return false
	}

	managerLogin := strings.TrimSpace(h.cfg.ManagerLogin)
	if managerLogin == "" || strings.TrimSpace(password) == "" {
		return false
	}

	account, ok := h.adminAccess.Authenticate(managerLogin, password)
	if !ok {
		return false
	}
	return adminaccess.HasPanelAccess(account.Permissions)
}

// isTelegramManagerFlowEnabled reports whether manager activation through the bot is configured.
func (h *Handler) isTelegramManagerFlowEnabled() bool {
	if h == nil || h.cfg == nil || h.adminAccess == nil {
		return false
	}
	if strings.TrimSpace(h.cfg.ManagerLogin) == "" {
		return false
	}
	return strings.TrimSpace(h.cfg.ManagerPassword) != "" ||
		strings.TrimSpace(h.cfg.ManagerPassHash) != ""
}

// mergeAdminPermissions normalizes and deduplicates permission lists.
func mergeAdminPermissions(groups ...[]string) []string {
	seen := make(map[string]struct{})
	out := make([]string, 0, len(groups))

	for _, group := range groups {
		for _, permission := range group {
			normalized := strings.ToLower(strings.TrimSpace(permission))
			if normalized == "" {
				continue
			}
			if _, ok := seen[normalized]; ok {
				continue
			}
			seen[normalized] = struct{}{}
			out = append(out, normalized)
		}
	}

	if len(out) == 0 {
		return nil
	}
	return out
}
