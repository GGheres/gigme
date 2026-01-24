package handlers

import (
	"net/http"

	"gigme/backend/internal/http/middleware"
)

func (h *Handler) Me(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.UserIDFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	user, err := h.repo.GetUserByID(ctx, userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	writeJSON(w, http.StatusOK, user)
}
