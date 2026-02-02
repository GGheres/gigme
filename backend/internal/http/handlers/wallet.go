package handlers

import (
	"encoding/json"
	"errors"
	"net/http"

	"gigme/backend/internal/http/middleware"
)

const maxTopupTokens int64 = 1_000_000

var errInvalidTopupAmount = errors.New("invalid topup amount")

type topupTokenRequest struct {
	Amount int64 `json:"amount"`
}

func validateTopupAmount(amount int64) error {
	if amount < 1 || amount > maxTopupTokens {
		return errInvalidTopupAmount
	}
	return nil
}

func (h *Handler) TopupToken(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	userID, ok := middleware.UserIDFromContext(r.Context())
	if !ok {
		logger.Warn("action", "action", "topup_token", "status", "unauthorized")
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	var req topupTokenRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		logger.Warn("action", "action", "topup_token", "status", "invalid_json")
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	if err := validateTopupAmount(req.Amount); err != nil {
		logger.Warn("action", "action", "topup_token", "status", "invalid_amount", "amount", req.Amount)
		writeError(w, http.StatusBadRequest, "invalid amount")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	balance, err := h.repo.AddUserTokens(ctx, userID, req.Amount)
	if err != nil {
		logger.Error("action", "action", "topup_token", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}

	logger.Info("action", "action", "topup_token", "status", "success", "amount", req.Amount, "balance", balance)
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"balanceTokens": balance,
	})
}

func (h *Handler) TopupCard(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := middleware.UserIDFromContext(r.Context()); !ok {
		logger.Warn("action", "action", "topup_card", "status", "unauthorized")
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	logger.Info("action", "action", "topup_card", "status", "not_implemented")
	writeError(w, http.StatusNotImplemented, "card topup not implemented")
}
