package handlers

import (
	"net/http"
	"strconv"

	"gigme/backend/internal/http/middleware"
)

// MyEvents handles my events.
func (h *Handler) MyEvents(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	userID, ok := middleware.UserIDFromContext(r.Context())
	if !ok {
		logger.Warn("action", "action", "events_mine", "status", "unauthorized")
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	limit := 20
	if v := r.URL.Query().Get("limit"); v != "" {
		if parsed, err := strconv.Atoi(v); err == nil && parsed > 0 {
			limit = parsed
		}
	}
	offset := 0
	if v := r.URL.Query().Get("offset"); v != "" {
		if parsed, err := strconv.Atoi(v); err == nil && parsed >= 0 {
			offset = parsed
		}
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	items, total, err := h.repo.ListUserEvents(ctx, userID, limit, offset)
	if err != nil {
		logger.Error("action", "action", "events_mine", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}

	logger.Info("action", "action", "events_mine", "status", "success", "limit", limit, "offset", offset, "count", len(items))
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"items": items,
		"total": total,
	})
}
