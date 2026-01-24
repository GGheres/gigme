package handlers

import (
	"encoding/json"
	"net/http"
	"strconv"

	"gigme/backend/internal/http/middleware"

	"github.com/go-chi/chi/v5"
)

type hideRequest struct {
	Hidden bool `json:"hidden"`
}

func (h *Handler) HideEvent(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	telegramID, ok := middleware.TelegramIDFromContext(r.Context())
	if !ok {
		logger.Warn("action", "action", "hide_event", "status", "unauthorized")
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	if _, allowed := h.cfg.AdminTGIDs[telegramID]; !allowed {
		logger.Warn("action", "action", "hide_event", "status", "forbidden", "telegram_id", telegramID)
		writeError(w, http.StatusForbidden, "forbidden")
		return
	}

	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		logger.Warn("action", "action", "hide_event", "status", "invalid_event_id")
		writeError(w, http.StatusBadRequest, "invalid event id")
		return
	}

	var req hideRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		logger.Warn("action", "action", "hide_event", "status", "invalid_json")
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	if err := h.repo.SetEventHidden(ctx, id, req.Hidden); err != nil {
		logger.Error("action", "action", "hide_event", "status", "db_error", "event_id", id, "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}

	logger.Info("action", "action", "hide_event", "status", "success", "event_id", id, "hidden", req.Hidden)
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}
