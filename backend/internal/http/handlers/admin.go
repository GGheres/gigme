package handlers

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"gigme/backend/internal/http/middleware"
	"gigme/backend/internal/models"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
)

type hideRequest struct {
	Hidden bool `json:"hidden"`
}

type updateEventRequest struct {
	Title              *string  `json:"title"`
	Description        *string  `json:"description"`
	StartsAt           *string  `json:"startsAt"`
	EndsAt             *string  `json:"endsAt"`
	Lat                *float64 `json:"lat"`
	Lng                *float64 `json:"lng"`
	Capacity           *int     `json:"capacity"`
	Media              []string `json:"media"`
	Address            *string  `json:"addressLabel"`
	Filters            []string `json:"filters"`
	ContactTelegram    *string  `json:"contactTelegram"`
	ContactWhatsapp    *string  `json:"contactWhatsapp"`
	ContactWechat      *string  `json:"contactWechat"`
	ContactFbMessenger *string  `json:"contactFbMessenger"`
	ContactSnapchat    *string  `json:"contactSnapchat"`
}

type adminBlockRequest struct {
	Reason string `json:"reason"`
}

type adminUsersResponse struct {
	Items []models.AdminUser `json:"items"`
	Total int                `json:"total"`
}

type adminUserDetailResponse struct {
	User          models.AdminUser   `json:"user"`
	CreatedEvents []models.UserEvent `json:"createdEvents"`
}

type broadcastButton struct {
	Text string `json:"text"`
	URL  string `json:"url"`
}

type broadcastFilters struct {
	Blocked       *bool   `json:"blocked"`
	MinBalance    *int64  `json:"minBalance"`
	LastSeenAfter *string `json:"lastSeenAfter"`
}

type createBroadcastRequest struct {
	Audience string            `json:"audience"`
	UserIDs  []int64           `json:"userIds"`
	Filters  *broadcastFilters `json:"filters"`
	Message  string            `json:"message"`
	Buttons  []broadcastButton `json:"buttons"`
}

type createBroadcastResponse struct {
	BroadcastID int64 `json:"broadcastId"`
	Targets     int64 `json:"targets"`
}

const maxBroadcastMessageLength = 4096

func (h *Handler) requireAdmin(logger *slog.Logger, w http.ResponseWriter, r *http.Request, action string) (int64, bool) {
	telegramID, ok := middleware.TelegramIDFromContext(r.Context())
	if !ok {
		logger.Warn("action", "action", action, "status", "unauthorized")
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return 0, false
	}
	if _, allowed := h.cfg.AdminTGIDs[telegramID]; !allowed {
		logger.Warn("action", "action", action, "status", "forbidden", "telegram_id", telegramID)
		writeError(w, http.StatusForbidden, "forbidden")
		return 0, false
	}
	return telegramID, true
}

func (h *Handler) ListAdminUsers(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_list_users"); !ok {
		return
	}
	search := strings.TrimSpace(r.URL.Query().Get("search"))
	limit := 50
	offset := 0
	if val := r.URL.Query().Get("limit"); val != "" {
		if parsed, err := strconv.Atoi(val); err == nil && parsed > 0 && parsed <= 200 {
			limit = parsed
		}
	}
	if val := r.URL.Query().Get("offset"); val != "" {
		if parsed, err := strconv.Atoi(val); err == nil && parsed >= 0 {
			offset = parsed
		}
	}
	var blocked *bool
	if val := strings.TrimSpace(r.URL.Query().Get("blocked")); val != "" {
		parsed := strings.ToLower(val)
		if parsed == "true" || parsed == "1" {
			v := true
			blocked = &v
		} else if parsed == "false" || parsed == "0" {
			v := false
			blocked = &v
		}
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	items, total, err := h.repo.ListAdminUsers(ctx, search, blocked, limit, offset)
	if err != nil {
		logger.Error("action", "action", "admin_list_users", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	writeJSON(w, http.StatusOK, adminUsersResponse{Items: items, Total: total})
}

func (h *Handler) GetAdminUser(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_get_user"); !ok {
		return
	}
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		logger.Warn("action", "action", "admin_get_user", "status", "invalid_user_id")
		writeError(w, http.StatusBadRequest, "invalid user id")
		return
	}
	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	user, err := h.repo.GetAdminUser(ctx, id)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			logger.Warn("action", "action", "admin_get_user", "status", "not_found", "user_id", id)
			writeError(w, http.StatusNotFound, "user not found")
			return
		}
		logger.Error("action", "action", "admin_get_user", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	events, _, err := h.repo.ListUserEvents(ctx, id, 100, 0)
	if err != nil {
		logger.Error("action", "action", "admin_get_user", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	writeJSON(w, http.StatusOK, adminUserDetailResponse{User: user, CreatedEvents: events})
}

func (h *Handler) BlockUser(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_block_user"); !ok {
		return
	}
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		logger.Warn("action", "action", "admin_block_user", "status", "invalid_user_id")
		writeError(w, http.StatusBadRequest, "invalid user id")
		return
	}
	var req adminBlockRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		logger.Warn("action", "action", "admin_block_user", "status", "invalid_json")
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	if err := h.repo.BlockUser(ctx, id, strings.TrimSpace(req.Reason)); err != nil {
		logger.Error("action", "action", "admin_block_user", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (h *Handler) UnblockUser(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_unblock_user"); !ok {
		return
	}
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		logger.Warn("action", "action", "admin_unblock_user", "status", "invalid_user_id")
		writeError(w, http.StatusBadRequest, "invalid user id")
		return
	}
	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	if err := h.repo.UnblockUser(ctx, id); err != nil {
		logger.Error("action", "action", "admin_unblock_user", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (h *Handler) CreateBroadcast(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_create_broadcast"); !ok {
		return
	}
	adminUserID, ok := middleware.UserIDFromContext(r.Context())
	if !ok {
		logger.Warn("action", "action", "admin_create_broadcast", "status", "unauthorized")
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	var req createBroadcastRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		logger.Warn("action", "action", "admin_create_broadcast", "status", "invalid_json")
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	req.Audience = strings.TrimSpace(req.Audience)
	message := strings.TrimSpace(req.Message)
	if message == "" || utf8.RuneCountInString(message) > maxBroadcastMessageLength {
		logger.Warn("action", "action", "admin_create_broadcast", "status", "invalid_message")
		writeError(w, http.StatusBadRequest, "message too long")
		return
	}

	payload := map[string]interface{}{
		"message": message,
	}
	if len(req.Buttons) > 0 {
		payload["buttons"] = req.Buttons
	}

	var targets int64
	var minBalance *int64
	var lastSeenAfter *time.Time
	switch req.Audience {
	case "all":
		// no extra validation
	case "selected":
		if len(req.UserIDs) == 0 {
			writeError(w, http.StatusBadRequest, "userIds required")
			return
		}
	case "filter":
		if req.Filters != nil {
			if req.Filters.Blocked != nil && *req.Filters.Blocked {
				writeError(w, http.StatusBadRequest, "blocked recipients not allowed")
				return
			}
			if req.Filters.MinBalance != nil {
				minBalance = req.Filters.MinBalance
			}
			if req.Filters.LastSeenAfter != nil && *req.Filters.LastSeenAfter != "" {
				parsed, err := time.Parse(time.RFC3339, *req.Filters.LastSeenAfter)
				if err != nil {
					writeError(w, http.StatusBadRequest, "invalid lastSeenAfter")
					return
				}
				lastSeenAfter = &parsed
			}
		}
	default:
		writeError(w, http.StatusBadRequest, "invalid audience")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	broadcastID, err := h.repo.CreateAdminBroadcast(ctx, adminUserID, req.Audience, payload)
	if err != nil {
		logger.Error("action", "action", "admin_create_broadcast", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}

	switch req.Audience {
	case "all":
		targets, err = h.repo.InsertAdminBroadcastJobsForAll(ctx, broadcastID)
	case "selected":
		targets, err = h.repo.InsertAdminBroadcastJobsForSelected(ctx, broadcastID, req.UserIDs)
	case "filter":
		targets, err = h.repo.InsertAdminBroadcastJobsForFilter(ctx, broadcastID, minBalance, lastSeenAfter)
	}
	if err != nil {
		_ = h.repo.UpdateAdminBroadcastStatus(ctx, broadcastID, "failed")
		logger.Error("action", "action", "admin_create_broadcast", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}

	writeJSON(w, http.StatusOK, createBroadcastResponse{BroadcastID: broadcastID, Targets: targets})
}

func (h *Handler) StartBroadcast(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_start_broadcast"); !ok {
		return
	}
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		logger.Warn("action", "action", "admin_start_broadcast", "status", "invalid_broadcast_id")
		writeError(w, http.StatusBadRequest, "invalid broadcast id")
		return
	}
	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	if _, err := h.repo.GetAdminBroadcast(ctx, id); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeError(w, http.StatusNotFound, "broadcast not found")
			return
		}
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	if err := h.repo.UpdateAdminBroadcastStatus(ctx, id, "processing"); err != nil {
		logger.Error("action", "action", "admin_start_broadcast", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	_, _ = h.repo.FinalizeAdminBroadcast(ctx, id)
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (h *Handler) ListBroadcasts(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_list_broadcasts"); !ok {
		return
	}
	limit := 50
	offset := 0
	if val := r.URL.Query().Get("limit"); val != "" {
		if parsed, err := strconv.Atoi(val); err == nil && parsed > 0 && parsed <= 200 {
			limit = parsed
		}
	}
	if val := r.URL.Query().Get("offset"); val != "" {
		if parsed, err := strconv.Atoi(val); err == nil && parsed >= 0 {
			offset = parsed
		}
	}
	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	items, total, err := h.repo.ListAdminBroadcasts(ctx, limit, offset)
	if err != nil {
		logger.Error("action", "action", "admin_list_broadcasts", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"items": items,
		"total": total,
	})
}

func (h *Handler) GetBroadcast(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_get_broadcast"); !ok {
		return
	}
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		logger.Warn("action", "action", "admin_get_broadcast", "status", "invalid_broadcast_id")
		writeError(w, http.StatusBadRequest, "invalid broadcast id")
		return
	}
	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	item, err := h.repo.GetAdminBroadcast(ctx, id)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeError(w, http.StatusNotFound, "broadcast not found")
			return
		}
		logger.Error("action", "action", "admin_get_broadcast", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	writeJSON(w, http.StatusOK, item)
}

func (h *Handler) HideEvent(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "hide_event"); !ok {
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

func (h *Handler) UpdateEventAdmin(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_update_event"); !ok {
		return
	}

	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		logger.Warn("action", "action", "admin_update_event", "status", "invalid_event_id")
		writeError(w, http.StatusBadRequest, "invalid event id")
		return
	}

	var req updateEventRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		logger.Warn("action", "action", "admin_update_event", "status", "invalid_json")
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}

	hasUpdate := req.Title != nil ||
		req.Description != nil ||
		req.StartsAt != nil ||
		req.EndsAt != nil ||
		req.Lat != nil ||
		req.Lng != nil ||
		req.Capacity != nil ||
		req.Media != nil ||
		req.Address != nil ||
		req.Filters != nil ||
		req.ContactTelegram != nil ||
		req.ContactWhatsapp != nil ||
		req.ContactWechat != nil ||
		req.ContactFbMessenger != nil ||
		req.ContactSnapchat != nil
	if !hasUpdate {
		logger.Warn("action", "action", "admin_update_event", "status", "no_updates")
		writeError(w, http.StatusBadRequest, "no updates provided")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()

	existing, err := h.repo.GetEventByID(ctx, id)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			logger.Warn("action", "action", "admin_update_event", "status", "not_found", "event_id", id)
			writeError(w, http.StatusNotFound, "event not found")
			return
		}
		logger.Error("action", "action", "admin_update_event", "status", "db_error", "event_id", id, "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}

	updated := existing

	if req.Title != nil {
		title := strings.TrimSpace(*req.Title)
		if title == "" || utf8.RuneCountInString(title) > maxTitleLength {
			logger.Warn("action", "action", "admin_update_event", "status", "invalid_title")
			writeError(w, http.StatusBadRequest, "title length invalid")
			return
		}
		updated.Title = title
	}

	if req.Description != nil {
		description := strings.TrimSpace(*req.Description)
		if description == "" || utf8.RuneCountInString(description) > maxDescriptionLength {
			logger.Warn("action", "action", "admin_update_event", "status", "invalid_description")
			writeError(w, http.StatusBadRequest, "description length invalid")
			return
		}
		updated.Description = description
	}

	if req.Lat != nil || req.Lng != nil {
		if req.Lat == nil || req.Lng == nil {
			logger.Warn("action", "action", "admin_update_event", "status", "invalid_coordinates")
			writeError(w, http.StatusBadRequest, "lat and lng required together")
			return
		}
		if *req.Lat < -90 || *req.Lat > 90 || *req.Lng < -180 || *req.Lng > 180 {
			logger.Warn("action", "action", "admin_update_event", "status", "invalid_coordinates")
			writeError(w, http.StatusBadRequest, "invalid coordinates")
			return
		}
		updated.Lat = *req.Lat
		updated.Lng = *req.Lng
	}

	if req.Capacity != nil {
		if *req.Capacity <= 0 {
			logger.Warn("action", "action", "admin_update_event", "status", "invalid_capacity")
			writeError(w, http.StatusBadRequest, "capacity must be > 0")
			return
		}
		updated.Capacity = req.Capacity
	}

	if req.Media != nil && len(req.Media) > 5 {
		logger.Warn("action", "action", "admin_update_event", "status", "media_limit_exceeded")
		writeError(w, http.StatusBadRequest, "media limit exceeded")
		return
	}

	if req.Filters != nil {
		filters, err := normalizeEventFilters(req.Filters, maxEventFilters)
		if err != nil {
			status := "invalid_filters"
			message := "invalid filters"
			if errors.Is(err, errTooManyFilters) {
				status = "filters_limit_exceeded"
				message = "filters limit exceeded"
			}
			logger.Warn("action", "action", "admin_update_event", "status", status)
			writeError(w, http.StatusBadRequest, message)
			return
		}
		if filters == nil {
			filters = []string{}
		}
		updated.Filters = filters
	}

	if req.ContactTelegram != nil {
		value := strings.TrimSpace(*req.ContactTelegram)
		if utf8.RuneCountInString(value) > maxContactLength {
			logger.Warn("action", "action", "admin_update_event", "status", "contact_telegram_too_long")
			writeError(w, http.StatusBadRequest, "contact telegram too long")
			return
		}
		updated.ContactTelegram = value
	}
	if req.ContactWhatsapp != nil {
		value := strings.TrimSpace(*req.ContactWhatsapp)
		if utf8.RuneCountInString(value) > maxContactLength {
			logger.Warn("action", "action", "admin_update_event", "status", "contact_whatsapp_too_long")
			writeError(w, http.StatusBadRequest, "contact whatsapp too long")
			return
		}
		updated.ContactWhatsapp = value
	}
	if req.ContactWechat != nil {
		value := strings.TrimSpace(*req.ContactWechat)
		if utf8.RuneCountInString(value) > maxContactLength {
			logger.Warn("action", "action", "admin_update_event", "status", "contact_wechat_too_long")
			writeError(w, http.StatusBadRequest, "contact wechat too long")
			return
		}
		updated.ContactWechat = value
	}
	if req.ContactFbMessenger != nil {
		value := strings.TrimSpace(*req.ContactFbMessenger)
		if utf8.RuneCountInString(value) > maxContactLength {
			logger.Warn("action", "action", "admin_update_event", "status", "contact_fb_messenger_too_long")
			writeError(w, http.StatusBadRequest, "contact fb messenger too long")
			return
		}
		updated.ContactFbMessenger = value
	}
	if req.ContactSnapchat != nil {
		value := strings.TrimSpace(*req.ContactSnapchat)
		if utf8.RuneCountInString(value) > maxContactLength {
			logger.Warn("action", "action", "admin_update_event", "status", "contact_snapchat_too_long")
			writeError(w, http.StatusBadRequest, "contact snapchat too long")
			return
		}
		updated.ContactSnapchat = value
	}

	if req.Address != nil {
		updated.AddressLabel = strings.TrimSpace(*req.Address)
	}

	startsAt := updated.StartsAt
	if req.StartsAt != nil {
		parsed, err := time.Parse(time.RFC3339, *req.StartsAt)
		if err != nil {
			logger.Warn("action", "action", "admin_update_event", "status", "invalid_starts_at")
			writeError(w, http.StatusBadRequest, "invalid startsAt")
			return
		}
		startsAt = parsed
		updated.StartsAt = parsed
	}

	endsAt := updated.EndsAt
	if req.EndsAt != nil {
		if strings.TrimSpace(*req.EndsAt) == "" {
			endsAt = nil
		} else {
			parsed, err := time.Parse(time.RFC3339, *req.EndsAt)
			if err != nil {
				logger.Warn("action", "action", "admin_update_event", "status", "invalid_ends_at")
				writeError(w, http.StatusBadRequest, "invalid endsAt")
				return
			}
			endsAt = &parsed
		}
	}
	if endsAt != nil && endsAt.Before(startsAt) {
		logger.Warn("action", "action", "admin_update_event", "status", "ends_before_starts")
		writeError(w, http.StatusBadRequest, "endsAt before startsAt")
		return
	}
	updated.EndsAt = endsAt

	replaceMedia := req.Media != nil
	if err := h.repo.UpdateEventWithMedia(ctx, updated, req.Media, replaceMedia); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			logger.Warn("action", "action", "admin_update_event", "status", "not_found", "event_id", id)
			writeError(w, http.StatusNotFound, "event not found")
			return
		}
		logger.Error("action", "action", "admin_update_event", "status", "db_error", "event_id", id, "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}

	logger.Info("action", "action", "admin_update_event", "status", "success", "event_id", id, "replace_media", replaceMedia)
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (h *Handler) DeleteEventAdmin(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_delete_event"); !ok {
		return
	}

	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		logger.Warn("action", "action", "admin_delete_event", "status", "invalid_event_id")
		writeError(w, http.StatusBadRequest, "invalid event id")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()

	if err := h.repo.DeleteEvent(ctx, id); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			logger.Warn("action", "action", "admin_delete_event", "status", "not_found", "event_id", id)
			writeError(w, http.StatusNotFound, "event not found")
			return
		}
		logger.Error("action", "action", "admin_delete_event", "status", "db_error", "event_id", id, "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}

	logger.Info("action", "action", "admin_delete_event", "status", "success", "event_id", id)
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}
