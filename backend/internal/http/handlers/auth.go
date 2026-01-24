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
	var req authRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	if err := h.validator.Struct(req); err != nil {
		writeError(w, http.StatusBadRequest, "initData required")
		return
	}

	user, _, err := auth.ValidateInitData(req.InitData, h.cfg.TelegramToken, 24*time.Hour)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "invalid initData")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()

	stored, err := h.repo.UpsertUser(ctx, models.User{
		TelegramID: user.ID,
		Username:   user.Username,
		FirstName:  user.FirstName,
		LastName:   user.LastName,
		PhotoURL:   user.PhotoURL,
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}

	token, err := auth.SignAccessToken(h.cfg.JWTSecret, stored.ID, stored.TelegramID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "token error")
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"accessToken": token,
		"user":        stored,
	})
}
