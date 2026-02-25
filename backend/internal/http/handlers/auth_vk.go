package handlers

import (
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"strings"
	"time"

	"gigme/backend/internal/auth"
	"gigme/backend/internal/integrations"
	"gigme/backend/internal/models"
)

// authVKRequest represents auth v k request.
type authVKRequest struct {
	AccessToken string `json:"accessToken"`
	UserID      *int64 `json:"userId"`
	Code        string `json:"code"`
	State       string `json:"state"`
	DeviceID    string `json:"deviceId"`
}

// authVKStartRequest represents auth v k start request.
type authVKStartRequest struct {
	RedirectURI string `json:"redirectUri"`
	Next        string `json:"next"`
}

// AuthVKStart authenticates v k start.
func (h *Handler) AuthVKStart(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)

	appID := strings.TrimSpace(h.cfg.VKAppID)
	if appID == "" {
		logger.Warn("action", "action", "auth_vk_start", "status", "disabled")
		writeError(w, http.StatusServiceUnavailable, "vk auth is disabled")
		return
	}

	var req authVKStartRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil && !errors.Is(err, io.EOF) {
		logger.Warn("action", "action", "auth_vk_start", "status", "invalid_json")
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}

	redirectURI := strings.TrimSpace(req.RedirectURI)
	if redirectURI == "" {
		redirectURI = strings.TrimSpace(r.URL.Query().Get("redirectUri"))
	}
	if redirectURI == "" {
		redirectURI = strings.TrimSpace(r.URL.Query().Get("redirect_uri"))
	}
	parsedRedirectURI, err := url.ParseRequestURI(redirectURI)
	if err != nil || parsedRedirectURI == nil || parsedRedirectURI.Host == "" {
		logger.Warn("action", "action", "auth_vk_start", "status", "invalid_redirect_uri")
		writeError(w, http.StatusBadRequest, "redirectUri is required")
		return
	}
	switch strings.ToLower(parsedRedirectURI.Scheme) {
	case "http", "https":
	default:
		logger.Warn("action", "action", "auth_vk_start", "status", "invalid_redirect_scheme")
		writeError(w, http.StatusBadRequest, "redirectUri scheme must be http or https")
		return
	}

	next := strings.TrimSpace(req.Next)
	if next == "" {
		next = strings.TrimSpace(r.URL.Query().Get("next"))
	}

	codeVerifier, err := auth.GeneratePKCECodeVerifier(64)
	if err != nil {
		logger.Error("action", "action", "auth_vk_start", "status", "pkce_error", "error", err)
		writeError(w, http.StatusInternalServerError, "vk auth setup failed")
		return
	}
	codeChallenge := auth.BuildPKCECodeChallenge(codeVerifier)

	signedState, err := auth.BuildVKOAuthState(
		h.cfg.JWTSecret,
		codeVerifier,
		parsedRedirectURI.String(),
		next,
		time.Now(),
	)
	if err != nil {
		logger.Error("action", "action", "auth_vk_start", "status", "state_error", "error", err)
		writeError(w, http.StatusInternalServerError, "vk auth setup failed")
		return
	}

	values := url.Values{}
	values.Set("response_type", "code")
	values.Set("client_id", appID)
	values.Set("redirect_uri", parsedRedirectURI.String())
	values.Set("state", signedState)
	values.Set("code_challenge", codeChallenge)
	values.Set("code_challenge_method", "S256")
	authorizeURL := (&url.URL{
		Scheme:   "https",
		Host:     "id.vk.ru",
		Path:     "/authorize",
		RawQuery: values.Encode(),
	}).String()

	logger.Info("action", "action", "auth_vk_start", "status", "success")
	writeJSON(w, http.StatusOK, map[string]string{
		"authorizeUrl": authorizeURL,
	})
}

// AuthVK authenticates v k.
func (h *Handler) AuthVK(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)

	var req authVKRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		logger.Warn("action", "action", "auth_vk", "status", "invalid_json")
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}

	req.AccessToken = strings.TrimSpace(req.AccessToken)
	req.Code = strings.TrimSpace(req.Code)
	req.State = strings.TrimSpace(req.State)
	req.DeviceID = strings.TrimSpace(req.DeviceID)

	legacyFlow := req.AccessToken != ""
	codeFlow := req.Code != "" || req.State != "" || req.DeviceID != ""
	switch {
	case legacyFlow:
		h.authVKLegacy(w, r, req, logger)
		return
	case codeFlow:
		h.authVKCodeFlow(w, r, req, logger)
		return
	default:
		logger.Warn("action", "action", "auth_vk", "status", "invalid_payload")
		writeError(w, http.StatusBadRequest, "accessToken or code/state/deviceId required")
		return
	}
}

// authVKLegacy authenticates v k legacy.
func (h *Handler) authVKLegacy(
	w http.ResponseWriter,
	r *http.Request,
	req authVKRequest,
	logger *slog.Logger,
) {
	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()

	vkUser, err := integrations.NewVKClient().GetUser(ctx, req.AccessToken)
	if err != nil {
		var vkAuthErr *integrations.VKAuthError
		if errors.As(err, &vkAuthErr) {
			logger.Warn(
				"action", "action", "auth_vk",
				"status", "invalid_access_token",
				"vk_error_code", vkAuthErr.Code,
				"error", vkAuthErr.Message,
			)
			writeError(w, http.StatusUnauthorized, "invalid vk access token")
			return
		}
		logger.Error("action", "action", "auth_vk", "status", "vk_lookup_failed", "error", err)
		writeError(w, http.StatusBadGateway, "vk lookup failed")
		return
	}

	if req.UserID != nil && *req.UserID > 0 && vkUser.ID != *req.UserID {
		logger.Warn(
			"action", "action", "auth_vk",
			"status", "user_mismatch",
			"requested_user_id", *req.UserID,
			"resolved_user_id", vkUser.ID,
		)
		writeError(w, http.StatusUnauthorized, "vk user mismatch")
		return
	}

	firstName := strings.TrimSpace(vkUser.FirstName)
	if firstName == "" {
		firstName = "VK User"
	}

	stored, isNew, err := h.repo.UpsertUser(ctx, models.User{
		TelegramID: vkExternalTelegramID(vkUser.ID),
		Username:   strings.TrimSpace(vkUser.ScreenName),
		FirstName:  firstName,
		LastName:   strings.TrimSpace(vkUser.LastName),
		PhotoURL:   strings.TrimSpace(vkUser.PhotoURL),
	})
	if err != nil {
		logger.Error("action", "action", "auth_vk", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}

	token, err := auth.SignAccessToken(h.cfg.JWTSecret, stored.ID, stored.TelegramID, isNew, false)
	if err != nil {
		logger.Error("action", "action", "auth_vk", "status", "token_error", "error", err)
		writeError(w, http.StatusInternalServerError, "token error")
		return
	}

	logger.Info(
		"action", "action", "auth_vk",
		"status", "success",
		"flow", "legacy_token",
		"user_id", stored.ID,
		"telegram_id", stored.TelegramID,
		"vk_user_id", vkUser.ID,
	)
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"accessToken": token,
		"user":        stored,
		"isNew":       isNew,
	})
}

// authVKCodeFlow authenticates v k code flow.
func (h *Handler) authVKCodeFlow(
	w http.ResponseWriter,
	r *http.Request,
	req authVKRequest,
	logger *slog.Logger,
) {
	if req.Code == "" || req.State == "" || req.DeviceID == "" {
		logger.Warn("action", "action", "auth_vk", "status", "invalid_code_payload")
		writeError(w, http.StatusBadRequest, "code, state and deviceId required")
		return
	}

	appID := strings.TrimSpace(h.cfg.VKAppID)
	if appID == "" {
		logger.Warn("action", "action", "auth_vk", "status", "disabled")
		writeError(w, http.StatusServiceUnavailable, "vk auth is disabled")
		return
	}

	state, err := auth.ParseVKOAuthState(req.State, h.cfg.JWTSecret, time.Now())
	if err != nil {
		logger.Warn("action", "action", "auth_vk", "status", "invalid_state")
		writeError(w, http.StatusUnauthorized, "invalid vk auth state")
		return
	}

	if _, err := url.ParseRequestURI(state.RedirectURI); err != nil {
		logger.Warn("action", "action", "auth_vk", "status", "invalid_redirect_uri")
		writeError(w, http.StatusUnauthorized, "invalid vk redirect uri")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()

	vkIDClient := integrations.NewVKIDClient(appID)
	tokenData, err := vkIDClient.ExchangeCode(
		ctx,
		req.Code,
		state.CodeVerifier,
		req.DeviceID,
		state.RedirectURI,
		req.State,
	)
	if err != nil {
		var vkIDAuthErr *integrations.VKIDAuthError
		if errors.As(err, &vkIDAuthErr) {
			logger.Warn(
				"action", "action", "auth_vk",
				"status", "code_exchange_failed",
				"vk_error", vkIDAuthErr.Code,
				"vk_error_description", vkIDAuthErr.Description,
				"http_status", vkIDAuthErr.StatusCode,
			)
			writeError(w, http.StatusUnauthorized, "invalid vk authorization code")
			return
		}
		logger.Error("action", "action", "auth_vk", "status", "code_exchange_failed", "error", err)
		writeError(w, http.StatusBadGateway, "vk code exchange failed")
		return
	}

	userInfo, userInfoErr := vkIDClient.GetUserInfo(ctx, tokenData.AccessToken)
	if userInfoErr != nil {
		logger.Warn(
			"action", "action", "auth_vk",
			"status", "user_info_failed",
			"error", userInfoErr,
		)
	}

	vkUserID := tokenData.UserID
	if userInfo.UserID > 0 {
		vkUserID = userInfo.UserID
	}
	if vkUserID <= 0 {
		logger.Warn("action", "action", "auth_vk", "status", "missing_user_id")
		writeError(w, http.StatusUnauthorized, "vk user id is missing")
		return
	}

	firstName := strings.TrimSpace(userInfo.FirstName)
	if firstName == "" {
		firstName = "VK User"
	}

	lastName := strings.TrimSpace(userInfo.LastName)
	photoURL := strings.TrimSpace(userInfo.Avatar)
	username := auth.BuildVKMiniAppUsername(vkUserID)

	stored, isNew, err := h.repo.UpsertUser(ctx, models.User{
		TelegramID: vkExternalTelegramID(vkUserID),
		Username:   username,
		FirstName:  firstName,
		LastName:   lastName,
		PhotoURL:   photoURL,
	})
	if err != nil {
		logger.Error("action", "action", "auth_vk", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}

	token, err := auth.SignAccessToken(h.cfg.JWTSecret, stored.ID, stored.TelegramID, isNew, false)
	if err != nil {
		logger.Error("action", "action", "auth_vk", "status", "token_error", "error", err)
		writeError(w, http.StatusInternalServerError, "token error")
		return
	}

	logger.Info(
		"action", "action", "auth_vk",
		"status", "success",
		"flow", "oauth_code",
		"user_id", stored.ID,
		"telegram_id", stored.TelegramID,
		"vk_user_id", vkUserID,
	)
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"accessToken": token,
		"user":        stored,
		"isNew":       isNew,
	})
}

// vkExternalTelegramID handles vk external telegram i d.
func vkExternalTelegramID(vkUserID int64) int64 {
	if vkUserID <= 0 {
		return -1
	}
	// Keep VK identities in the existing users.telegram_id column
	// without colliding with regular Telegram users (they are positive).
	return -vkUserID
}
