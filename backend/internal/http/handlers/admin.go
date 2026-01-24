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
	telegramID, ok := middleware.TelegramIDFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	if _, allowed := h.cfg.AdminTGIDs[telegramID]; !allowed {
		writeError(w, http.StatusForbidden, "forbidden")
		return
	}

	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid event id")
		return
	}

	var req hideRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	if err := h.repo.SetEventHidden(ctx, id, req.Hidden); err != nil {
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}

	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}
