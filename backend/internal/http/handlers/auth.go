package handlers

import (
	"encoding/json"
	"net/http"
	"time"

	"gigme/backend/internal/auth"
	"gigme/backend/internal/models"
)

type authRequest struct {
	InitData string `json:"initData" validate:"required"`
}

func (h *Handler) AuthTelegram(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	var req authRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		logger.Warn("action", "action", "auth_telegram", "status", "invalid_json")
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	if err := h.validator.Struct(req); err != nil {
		logger.Warn("action", "action", "auth_telegram", "status", "invalid_init_data")
		writeError(w, http.StatusBadRequest, "initData required")
		return
	}

	user, _, err := auth.ValidateInitData(req.InitData, h.cfg.TelegramToken, 24*time.Hour)
	if err != nil {
		logger.Warn("action", "action", "auth_telegram", "status", "invalid_init_data")
		writeError(w, http.StatusUnauthorized, "invalid initData")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()

	stored, isNew, err := h.repo.UpsertUser(ctx, models.User{
		TelegramID: user.ID,
		Username:   user.Username,
		FirstName:  user.FirstName,
		LastName:   user.LastName,
		PhotoURL:   user.PhotoURL,
	})
	if err != nil {
		logger.Error("action", "action", "auth_telegram", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}

	token, err := auth.SignAccessToken(h.cfg.JWTSecret, stored.ID, stored.TelegramID, isNew, false)
	if err != nil {
		logger.Error("action", "action", "auth_telegram", "status", "token_error", "error", err)
		writeError(w, http.StatusInternalServerError, "token error")
		return
	}

	logger.Info("action", "action", "auth_telegram", "status", "success", "user_id", stored.ID, "telegram_id", stored.TelegramID)
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"accessToken": token,
		"user":        stored,
		"isNew":       isNew,
	})
}
