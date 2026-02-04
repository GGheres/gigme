package handlers

import (
	"encoding/json"
	"net/http"

	"gigme/backend/internal/http/middleware"
)

type updateLocationRequest struct {
	Lat float64 `json:"lat"`
	Lng float64 `json:"lng"`
}

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
