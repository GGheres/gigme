package handlers

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"gigme/backend/internal/auth"
	"gigme/backend/internal/integrations"
	"gigme/backend/internal/models"
)

type authVKRequest struct {
	AccessToken string `json:"accessToken" validate:"required"`
	UserID      *int64 `json:"userId"`
}

func (h *Handler) AuthVK(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)

	var req authVKRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		logger.Warn("action", "action", "auth_vk", "status", "invalid_json")
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	if err := h.validator.Struct(req); err != nil {
		logger.Warn("action", "action", "auth_vk", "status", "invalid_payload")
		writeError(w, http.StatusBadRequest, "accessToken required")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()

	vkUser, err := integrations.NewVKClient().GetUser(ctx, req.AccessToken)
	if err != nil {
		var vkAuthErr *integrations.VKAuthError
		if errors.As(err, &vkAuthErr) {
			logger.Warn(
				"action", "action", "auth_vk",
				"status", "invalid_access_token",
				"vk_error_code", vkAuthErr.Code,
				"error", vkAuthErr.Message,
			)
			writeError(w, http.StatusUnauthorized, "invalid vk access token")
			return
		}
		logger.Error("action", "action", "auth_vk", "status", "vk_lookup_failed", "error", err)
		writeError(w, http.StatusBadGateway, "vk lookup failed")
		return
	}

	if req.UserID != nil && *req.UserID > 0 && vkUser.ID != *req.UserID {
		logger.Warn(
			"action", "action", "auth_vk",
			"status", "user_mismatch",
			"requested_user_id", *req.UserID,
			"resolved_user_id", vkUser.ID,
		)
		writeError(w, http.StatusUnauthorized, "vk user mismatch")
		return
	}

	firstName := strings.TrimSpace(vkUser.FirstName)
	if firstName == "" {
		firstName = "VK User"
	}

	stored, isNew, err := h.repo.UpsertUser(ctx, models.User{
		TelegramID: vkExternalTelegramID(vkUser.ID),
		Username:   strings.TrimSpace(vkUser.ScreenName),
		FirstName:  firstName,
		LastName:   strings.TrimSpace(vkUser.LastName),
		PhotoURL:   strings.TrimSpace(vkUser.PhotoURL),
	})
	if err != nil {
		logger.Error("action", "action", "auth_vk", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}

	token, err := auth.SignAccessToken(h.cfg.JWTSecret, stored.ID, stored.TelegramID, isNew, false)
	if err != nil {
		logger.Error("action", "action", "auth_vk", "status", "token_error", "error", err)
		writeError(w, http.StatusInternalServerError, "token error")
		return
	}

	logger.Info(
		"action", "action", "auth_vk",
		"status", "success",
		"user_id", stored.ID,
		"telegram_id", stored.TelegramID,
		"vk_user_id", vkUser.ID,
	)
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"accessToken": token,
		"user":        stored,
		"isNew":       isNew,
	})
}

func vkExternalTelegramID(vkUserID int64) int64 {
	if vkUserID <= 0 {
		return -1
	}
	// Keep VK identities in the existing users.telegram_id column
	// without colliding with regular Telegram users (they are positive).
	return -vkUserID
}
