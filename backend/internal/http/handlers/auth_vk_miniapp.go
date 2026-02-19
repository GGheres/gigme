package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"gigme/backend/internal/auth"
	"gigme/backend/internal/models"

	"github.com/jackc/pgx/v5"
)

type authVKMiniAppRequest struct {
	LaunchParams string `json:"launchParams" validate:"required"`
}

func (h *Handler) AuthVKMiniApp(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)

	if strings.TrimSpace(h.cfg.VKAppSecret) == "" {
		logger.Warn("action", "action", "auth_vk_miniapp", "status", "disabled")
		writeError(w, http.StatusServiceUnavailable, "vk mini app auth is disabled")
		return
	}

	var req authVKMiniAppRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		logger.Warn("action", "action", "auth_vk_miniapp", "status", "invalid_json")
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	if err := h.validator.Struct(req); err != nil {
		logger.Warn("action", "action", "auth_vk_miniapp", "status", "invalid_payload")
		writeError(w, http.StatusBadRequest, "launchParams required")
		return
	}

	launch, err := auth.ValidateVKLaunchParams(req.LaunchParams, h.cfg.VKAppSecret)
	if err != nil {
		logger.Warn("action", "action", "auth_vk_miniapp", "status", "invalid_launch_params")
		writeError(w, http.StatusUnauthorized, "invalid vk launch params")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()

	telegramID := vkExternalTelegramID(launch.UserID)
	stored, isNew, err := h.ensureVKMiniAppUser(ctx, launch.UserID, telegramID)
	if err != nil {
		logger.Error("action", "action", "auth_vk_miniapp", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}

	token, err := auth.SignAccessToken(h.cfg.JWTSecret, stored.ID, stored.TelegramID, isNew, false)
	if err != nil {
		logger.Error("action", "action", "auth_vk_miniapp", "status", "token_error", "error", err)
		writeError(w, http.StatusInternalServerError, "token error")
		return
	}

	logger.Info(
		"action", "action", "auth_vk_miniapp",
		"status", "success",
		"user_id", stored.ID,
		"telegram_id", stored.TelegramID,
		"vk_user_id", launch.UserID,
		"vk_app_id", launch.AppID,
		"vk_platform", launch.Platform,
	)
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"accessToken": token,
		"user":        stored,
		"isNew":       isNew,
	})
}

func (h *Handler) ensureVKMiniAppUser(ctx context.Context, vkUserID int64, telegramID int64) (models.User, bool, error) {
	existing, err := h.repo.GetUserByTelegramID(ctx, telegramID)
	if err == nil {
		return existing, false, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return models.User{}, false, err
	}

	created, err := h.repo.EnsureUserByTelegramID(
		ctx,
		telegramID,
		auth.BuildVKMiniAppUsername(vkUserID),
		"VK User",
		"",
	)
	if err != nil {
		return models.User{}, false, err
	}
	return created, true, nil
}
