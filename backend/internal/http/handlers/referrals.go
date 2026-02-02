package handlers

import (
	"encoding/json"
	"net/http"
	"strings"

	"gigme/backend/internal/http/middleware"
)

const referralBonusTokens int64 = 100

const maxReferralCodeLength = 32

type referralClaimRequest struct {
	EventID int64  `json:"eventId"`
	RefCode string `json:"refCode"`
}

func (h *Handler) ReferralCode(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	userID, ok := middleware.UserIDFromContext(r.Context())
	if !ok {
		logger.Warn("action", "action", "referral_code", "status", "unauthorized")
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	code, err := h.repo.GetOrCreateReferralCode(ctx, userID)
	if err != nil {
		logger.Error("action", "action", "referral_code", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}

	logger.Info("action", "action", "referral_code", "status", "success")
	writeJSON(w, http.StatusOK, map[string]string{"code": code})
}

func (h *Handler) ClaimReferral(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	userID, ok := middleware.UserIDFromContext(r.Context())
	if !ok {
		logger.Warn("action", "action", "referral_claim", "status", "unauthorized")
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	isNew, _ := middleware.IsNewFromContext(r.Context())

	var req referralClaimRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		logger.Warn("action", "action", "referral_claim", "status", "invalid_json")
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}

	req.RefCode = strings.TrimSpace(req.RefCode)
	if req.EventID <= 0 || req.RefCode == "" || len(req.RefCode) > maxReferralCodeLength {
		logger.Warn("action", "action", "referral_claim", "status", "invalid_request")
		writeError(w, http.StatusBadRequest, "invalid request")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	awarded, inviterBalance, inviteeBalance, err := h.repo.ClaimReferral(ctx, userID, req.EventID, req.RefCode, referralBonusTokens, isNew)
	if err != nil {
		logger.Error("action", "action", "referral_claim", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}

	if !awarded {
		logger.Info("action", "action", "referral_claim", "status", "no_award")
		writeJSON(w, http.StatusOK, map[string]bool{"awarded": false})
		return
	}

	logger.Info("action", "action", "referral_claim", "status", "awarded", "bonus", referralBonusTokens)
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"awarded":              true,
		"bonus":                referralBonusTokens,
		"inviterBalanceTokens": inviterBalance,
		"inviteeBalanceTokens": inviteeBalance,
	})
}
