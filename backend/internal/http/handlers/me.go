package handlers

import (
	"encoding/json"
	"net/http"
	"strings"

	"gigme/backend/internal/http/middleware"
	"gigme/backend/internal/models"
)

// updateLocationRequest represents update location request.
type updateLocationRequest struct {
	Lat float64 `json:"lat"`
	Lng float64 `json:"lng"`
}

// updatePushTokenRequest represents update push token request.
type updatePushTokenRequest struct {
	Token      string `json:"token"`
	Platform   string `json:"platform"`
	DeviceID   string `json:"deviceId"`
	AppVersion string `json:"appVersion"`
	Locale     string `json:"locale"`
}

// Me handles internal me behavior.
func (h *Handler) Me(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	userID, ok := middleware.UserIDFromContext(r.Context())
	if !ok {
		logger.Warn("action", "action", "me", "status", "unauthorized")
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	if err := h.repo.TouchUserLastSeen(ctx, userID); err != nil {
		logger.Error("action", "action", "me", "status", "last_seen_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	user, err := h.repo.GetUserByID(ctx, userID)
	if err != nil {
		logger.Error("action", "action", "me", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	logger.Info("action", "action", "me", "status", "success")
	writeJSON(w, http.StatusOK, user)
}

// UpdateLocation updates location.
func (h *Handler) UpdateLocation(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	userID, ok := middleware.UserIDFromContext(r.Context())
	if !ok {
		logger.Warn("action", "action", "update_location", "status", "unauthorized")
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	var req updateLocationRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		logger.Warn("action", "action", "update_location", "status", "invalid_json")
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	if req.Lat < -90 || req.Lat > 90 || req.Lng < -180 || req.Lng > 180 {
		logger.Warn("action", "action", "update_location", "status", "invalid_coordinates")
		writeError(w, http.StatusBadRequest, "invalid coordinates")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	if err := h.repo.UpdateUserLocation(ctx, userID, req.Lat, req.Lng); err != nil {
		logger.Error("action", "action", "update_location", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}

	logger.Info("action", "action", "update_location", "status", "success", "lat", req.Lat, "lng", req.Lng)
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

// UpsertPushToken handles upsert push token.
func (h *Handler) UpsertPushToken(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	userID, ok := middleware.UserIDFromContext(r.Context())
	if !ok {
		logger.Warn("action", "action", "upsert_push_token", "status", "unauthorized")
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	var req updatePushTokenRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		logger.Warn("action", "action", "upsert_push_token", "status", "invalid_json")
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}

	req.Token = strings.TrimSpace(req.Token)
	req.Platform = strings.ToLower(strings.TrimSpace(req.Platform))
	req.DeviceID = strings.TrimSpace(req.DeviceID)
	req.AppVersion = strings.TrimSpace(req.AppVersion)
	req.Locale = strings.TrimSpace(req.Locale)

	if req.Token == "" || len(req.Token) < 16 || len(req.Token) > 4096 {
		writeError(w, http.StatusBadRequest, "invalid token")
		return
	}
	if req.Platform != "android" && req.Platform != "ios" && req.Platform != "web" {
		writeError(w, http.StatusBadRequest, "invalid platform")
		return
	}
	if len(req.DeviceID) > 256 {
		writeError(w, http.StatusBadRequest, "deviceId too long")
		return
	}
	if len(req.AppVersion) > 128 {
		writeError(w, http.StatusBadRequest, "appVersion too long")
		return
	}
	if len(req.Locale) > 64 {
		writeError(w, http.StatusBadRequest, "locale too long")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	if err := h.repo.UpsertUserPushToken(ctx, models.UserPushToken{
		UserID:     userID,
		Platform:   req.Platform,
		Token:      req.Token,
		DeviceID:   req.DeviceID,
		AppVersion: req.AppVersion,
		Locale:     req.Locale,
		IsActive:   true,
	}); err != nil {
		logger.Error("action", "action", "upsert_push_token", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}

	logger.Info("action", "action", "upsert_push_token", "status", "success", "platform", req.Platform)
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}
