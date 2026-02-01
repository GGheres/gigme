package handlers

import (
	"encoding/json"
	"errors"
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

type createEventRequest struct {
	Title              string   `json:"title"`
	Description        string   `json:"description"`
	StartsAt           string   `json:"startsAt"`
	EndsAt             *string  `json:"endsAt"`
	Lat                float64  `json:"lat"`
	Lng                float64  `json:"lng"`
	Capacity           *int     `json:"capacity"`
	Media              []string `json:"media"`
	Address            string   `json:"addressLabel"`
	Filters            []string `json:"filters"`
	ContactTelegram    string   `json:"contactTelegram"`
	ContactWhatsapp    string   `json:"contactWhatsapp"`
	ContactWechat      string   `json:"contactWechat"`
	ContactFbMessenger string   `json:"contactFbMessenger"`
	ContactSnapchat    string   `json:"contactSnapchat"`
}

type promoteEventRequest struct {
	PromotedUntil   *string `json:"promotedUntil"`
	DurationMinutes *int    `json:"durationMinutes"`
	Clear           bool    `json:"clear"`
}

type commentRequest struct {
	Body string `json:"body"`
}

const maxEventFilters = 3
const maxContactLength = 120
const maxEventsPerHour = 3
const maxTitleLength = 80
const maxDescriptionLength = 1000
const maxCommentLength = 400

var allowedEventFilters = map[string]struct{}{
	"dating":   {},
	"party":    {},
	"travel":   {},
	"fun":      {},
	"bar":      {},
	"feedme":   {},
	"sport":    {},
	"study":    {},
	"business": {},
}

var (
	errInvalidFilters = errors.New("invalid filters")
	errTooManyFilters = errors.New("too many filters")
)

func normalizeEventFilters(filters []string, limit int) ([]string, error) {
	if len(filters) == 0 {
		return nil, nil
	}
	out := make([]string, 0, len(filters))
	seen := make(map[string]struct{}, len(filters))
	for _, raw := range filters {
		if raw == "" {
			continue
		}
		for _, piece := range strings.Split(raw, ",") {
			filter := strings.ToLower(strings.TrimSpace(piece))
			if filter == "" {
				continue
			}
			if _, ok := allowedEventFilters[filter]; !ok {
				return nil, errInvalidFilters
			}
			if _, exists := seen[filter]; exists {
				continue
			}
			out = append(out, filter)
			seen[filter] = struct{}{}
			if limit > 0 && len(out) > limit {
				return nil, errTooManyFilters
			}
		}
	}
	return out, nil
}

func parseEventFiltersQuery(r *http.Request) ([]string, error) {
	raw := r.URL.Query().Get("filters")
	if raw == "" {
		return nil, nil
	}
	return normalizeEventFilters([]string{raw}, 0)
}

func (h *Handler) CreateEvent(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	userID, ok := middleware.UserIDFromContext(r.Context())
	if !ok {
		logger.Warn("action", "action", "create_event", "status", "unauthorized")
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	var req createEventRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		logger.Warn("action", "action", "create_event", "status", "invalid_json")
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}

	title := strings.TrimSpace(req.Title)
	if title == "" || utf8.RuneCountInString(title) > maxTitleLength {
		logger.Warn("action", "action", "create_event", "status", "invalid_title")
		writeError(w, http.StatusBadRequest, "title length invalid")
		return
	}
	description := strings.TrimSpace(req.Description)
	if description == "" || utf8.RuneCountInString(description) > maxDescriptionLength {
		logger.Warn("action", "action", "create_event", "status", "invalid_description")
		writeError(w, http.StatusBadRequest, "description length invalid")
		return
	}
	if req.Lat < -90 || req.Lat > 90 || req.Lng < -180 || req.Lng > 180 {
		logger.Warn("action", "action", "create_event", "status", "invalid_coordinates")
		writeError(w, http.StatusBadRequest, "invalid coordinates")
		return
	}
	if req.Capacity != nil && *req.Capacity <= 0 {
		logger.Warn("action", "action", "create_event", "status", "invalid_capacity")
		writeError(w, http.StatusBadRequest, "capacity must be > 0")
		return
	}
	if len(req.Media) > 5 {
		logger.Warn("action", "action", "create_event", "status", "media_limit_exceeded")
		writeError(w, http.StatusBadRequest, "media limit exceeded")
		return
	}
	filters, err := normalizeEventFilters(req.Filters, maxEventFilters)
	if err != nil {
		status := "invalid_filters"
		message := "invalid filters"
		if errors.Is(err, errTooManyFilters) {
			status = "filters_limit_exceeded"
			message = "filters limit exceeded"
		}
		logger.Warn("action", "action", "create_event", "status", status)
		writeError(w, http.StatusBadRequest, message)
		return
	}
	if filters == nil {
		filters = []string{}
	}

	contactTelegram := strings.TrimSpace(req.ContactTelegram)
	if utf8.RuneCountInString(contactTelegram) > maxContactLength {
		logger.Warn("action", "action", "create_event", "status", "contact_telegram_too_long")
		writeError(w, http.StatusBadRequest, "contact telegram too long")
		return
	}
	contactWhatsapp := strings.TrimSpace(req.ContactWhatsapp)
	if utf8.RuneCountInString(contactWhatsapp) > maxContactLength {
		logger.Warn("action", "action", "create_event", "status", "contact_whatsapp_too_long")
		writeError(w, http.StatusBadRequest, "contact whatsapp too long")
		return
	}
	contactWechat := strings.TrimSpace(req.ContactWechat)
	if utf8.RuneCountInString(contactWechat) > maxContactLength {
		logger.Warn("action", "action", "create_event", "status", "contact_wechat_too_long")
		writeError(w, http.StatusBadRequest, "contact wechat too long")
		return
	}
	contactFbMessenger := strings.TrimSpace(req.ContactFbMessenger)
	if utf8.RuneCountInString(contactFbMessenger) > maxContactLength {
		logger.Warn("action", "action", "create_event", "status", "contact_fb_messenger_too_long")
		writeError(w, http.StatusBadRequest, "contact fb messenger too long")
		return
	}
	contactSnapchat := strings.TrimSpace(req.ContactSnapchat)
	if utf8.RuneCountInString(contactSnapchat) > maxContactLength {
		logger.Warn("action", "action", "create_event", "status", "contact_snapchat_too_long")
		writeError(w, http.StatusBadRequest, "contact snapchat too long")
		return
	}

	startsAt, err := time.Parse(time.RFC3339, req.StartsAt)
	if err != nil {
		logger.Warn("action", "action", "create_event", "status", "invalid_starts_at")
		writeError(w, http.StatusBadRequest, "invalid startsAt")
		return
	}
	var endsAt *time.Time
	if req.EndsAt != nil && *req.EndsAt != "" {
		parsed, err := time.Parse(time.RFC3339, *req.EndsAt)
		if err != nil {
			logger.Warn("action", "action", "create_event", "status", "invalid_ends_at")
			writeError(w, http.StatusBadRequest, "invalid endsAt")
			return
		}
		if parsed.Before(startsAt) {
			logger.Warn("action", "action", "create_event", "status", "ends_before_starts")
			writeError(w, http.StatusBadRequest, "endsAt before startsAt")
			return
		}
		endsAt = &parsed
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()

	count, err := h.repo.CountUserEventsLastHour(ctx, userID)
	if err != nil {
		logger.Error("action", "action", "create_event", "status", "rate_limit_check_failed", "error", err)
		writeError(w, http.StatusInternalServerError, "rate limit check failed")
		return
	}
	if count >= maxEventsPerHour {
		logger.Warn("action", "action", "create_event", "status", "rate_limited")
		writeError(w, http.StatusTooManyRequests, "event create limit reached")
		return
	}

	addressLabel := strings.TrimSpace(req.Address)
	eventID, err := h.repo.CreateEventWithMedia(ctx, models.Event{
		CreatorUserID:      userID,
		Title:              title,
		Description:        description,
		StartsAt:           startsAt,
		EndsAt:             endsAt,
		Lat:                req.Lat,
		Lng:                req.Lng,
		Capacity:           req.Capacity,
		AddressLabel:       addressLabel,
		ContactTelegram:    contactTelegram,
		ContactWhatsapp:    contactWhatsapp,
		ContactWechat:      contactWechat,
		ContactFbMessenger: contactFbMessenger,
		ContactSnapchat:    contactSnapchat,
		Filters:            filters,
	}, req.Media)
	if err != nil {
		logger.Error("action", "action", "create_event", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "failed to create event")
		return
	}

	_ = h.repo.JoinEvent(ctx, eventID, userID)

	payload := map[string]interface{}{
		"eventId":  eventID,
		"title":    title,
		"startsAt": req.StartsAt,
	}
	if apiBaseURL := strings.TrimSpace(h.cfg.APIPublicURL); apiBaseURL != "" {
		payload["apiBaseUrl"] = apiBaseURL
	} else if apiBaseURL := publicBaseURL(r); apiBaseURL != "" {
		payload["apiBaseUrl"] = apiBaseURL
	}
	if addressLabel != "" {
		payload["addressLabel"] = addressLabel
	}
	if len(req.Media) > 0 {
		payload["photoUrl"] = req.Media[0]
	}
	if count, err := h.repo.CreateNotificationJobsForAllUsers(ctx, eventID, "event_created", time.Now(), payload); err != nil {
		logger.Warn("action", "action", "create_event", "status", "notify_all_failed", "error", err)
	} else {
		logger.Info("action", "action", "create_event", "status", "notify_all_enqueued", "count", count)
	}

	reminderAt := startsAt.Add(-60 * time.Minute)
	if reminderAt.After(time.Now()) {
		_, _ = h.repo.CreateNotificationJob(ctx, models.NotificationJob{
			UserID:  userID,
			EventID: &eventID,
			Kind:    "reminder_60m",
			RunAt:   reminderAt,
			Payload: map[string]interface{}{"eventId": eventID, "title": title},
			Status:  "pending",
		})
	}

	logger.Info(
		"action",
		"action", "create_event",
		"status", "success",
		"event_id", eventID,
		"title", title,
		"starts_at", startsAt,
		"ends_at", endsAt,
		"lat", req.Lat,
		"lng", req.Lng,
		"capacity", req.Capacity,
		"media_count", len(req.Media),
		"filters", filters,
	)
	writeJSON(w, http.StatusOK, map[string]interface{}{"eventId": eventID})
}

func (h *Handler) NearbyEvents(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	var from *time.Time
	if v := r.URL.Query().Get("from"); v != "" {
		if parsed, err := time.Parse(time.RFC3339, v); err == nil {
			from = &parsed
		}
	}
	var to *time.Time
	if v := r.URL.Query().Get("to"); v != "" {
		if parsed, err := time.Parse(time.RFC3339, v); err == nil {
			to = &parsed
		}
	}
	lat, lng := parseLatLng(r)
	radius := parseRadiusM(r)
	filters, err := parseEventFiltersQuery(r)
	if err != nil {
		logger.Warn("action", "action", "nearby_events", "status", "invalid_filters")
		writeError(w, http.StatusBadRequest, "invalid filters")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	markers, err := h.repo.GetEventMarkers(ctx, from, to, lat, lng, radius, filters)
	if err != nil {
		logger.Error("action", "action", "nearby_events", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	logger.Info("action", "action", "nearby_events", "status", "success", "scope", "global", "count", len(markers))
	writeJSON(w, http.StatusOK, markers)
}

func (h *Handler) Feed(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	userID, _ := middleware.UserIDFromContext(r.Context())
	limit := 50
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
	lat, lng := parseLatLng(r)
	radius := parseRadiusM(r)
	filters, err := parseEventFiltersQuery(r)
	if err != nil {
		logger.Warn("action", "action", "feed", "status", "invalid_filters")
		writeError(w, http.StatusBadRequest, "invalid filters")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	items, err := h.repo.GetFeed(ctx, userID, limit, offset, lat, lng, radius, filters)
	if err != nil {
		logger.Error("action", "action", "feed", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	logger.Info("action", "action", "feed", "status", "success", "scope", "global", "limit", limit, "offset", offset, "count", len(items))
	writeJSON(w, http.StatusOK, items)
}

func (h *Handler) GetEvent(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	eventID, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		logger.Warn("action", "action", "get_event", "status", "invalid_event_id")
		writeError(w, http.StatusBadRequest, "invalid event id")
		return
	}
	userID, _ := middleware.UserIDFromContext(r.Context())

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()

	event, err := h.repo.GetEventByID(ctx, eventID)
	if err != nil {
		logger.Warn("action", "action", "get_event", "status", "not_found", "event_id", eventID)
		writeError(w, http.StatusNotFound, "event not found")
		return
	}
	if event.IsHidden {
		logger.Warn("action", "action", "get_event", "status", "hidden", "event_id", eventID)
		writeError(w, http.StatusNotFound, "event not found")
		return
	}

	participants, err := h.repo.GetParticipantsPreview(ctx, eventID, 10)
	if err != nil {
		logger.Error("action", "action", "get_event", "status", "participants_error", "event_id", eventID, "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	media, err := h.repo.ListEventMedia(ctx, eventID)
	if err != nil {
		logger.Error("action", "action", "get_event", "status", "media_error", "event_id", eventID, "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	isJoined := false
	if userID != 0 {
		joined, err := h.repo.IsUserJoined(ctx, eventID, userID)
		if err == nil {
			isJoined = joined
		}
	}
	isLiked := false
	if userID != 0 {
		liked, err := h.repo.IsEventLiked(ctx, eventID, userID)
		if err == nil {
			isLiked = liked
		}
	}
	event.IsLiked = isLiked

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"event":        event,
		"participants": participants,
		"media":        media,
		"isJoined":     isJoined,
	})
	logger.Info("action", "action", "get_event", "status", "success", "event_id", eventID, "user_id", userID, "participants_count", len(participants), "media_count", len(media))
}

func (h *Handler) JoinEvent(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	userID, ok := middleware.UserIDFromContext(r.Context())
	if !ok {
		logger.Warn("action", "action", "join_event", "status", "unauthorized")
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	if !h.joinLeaveLimiter.Allow(strconv.FormatInt(userID, 10)) {
		logger.Warn("action", "action", "join_event", "status", "rate_limited")
		writeError(w, http.StatusTooManyRequests, "rate limit")
		return
	}
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		logger.Warn("action", "action", "join_event", "status", "invalid_event_id")
		writeError(w, http.StatusBadRequest, "invalid event id")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()

	cap, err := h.repo.GetEventCapacity(ctx, id)
	if err != nil {
		logger.Warn("action", "action", "join_event", "status", "not_found", "event_id", id)
		writeError(w, http.StatusNotFound, "event not found")
		return
	}
	if cap != nil {
		count, err := h.repo.CountParticipants(ctx, id)
		if err != nil {
			logger.Error("action", "action", "join_event", "status", "count_error", "event_id", id, "error", err)
			writeError(w, http.StatusInternalServerError, "db error")
			return
		}
		if count >= *cap {
			logger.Warn("action", "action", "join_event", "status", "capacity_full", "event_id", id)
			writeError(w, http.StatusBadRequest, "event capacity full")
			return
		}
	}

	if err := h.repo.JoinEvent(ctx, id, userID); err != nil {
		logger.Error("action", "action", "join_event", "status", "db_error", "event_id", id, "error", err)
		writeError(w, http.StatusInternalServerError, "join failed")
		return
	}

	if title, err := h.repo.GetEventTitle(ctx, id); err == nil {
		_, _ = h.repo.CreateNotificationJob(ctx, models.NotificationJob{
			UserID:  userID,
			EventID: &id,
			Kind:    "joined",
			RunAt:   time.Now(),
			Payload: map[string]interface{}{"eventId": id, "title": title},
			Status:  "pending",
		})
		if startsAt, err := h.repo.GetEventStart(ctx, id); err == nil {
			reminderAt := startsAt.Add(-60 * time.Minute)
			if reminderAt.After(time.Now()) {
				_, _ = h.repo.CreateNotificationJob(ctx, models.NotificationJob{
					UserID:  userID,
					EventID: &id,
					Kind:    "reminder_60m",
					RunAt:   reminderAt,
					Payload: map[string]interface{}{"eventId": id, "title": title},
					Status:  "pending",
				})
			}
		}
	}

	logger.Info("action", "action", "join_event", "status", "success", "event_id", id)
	writeJSON(w, http.StatusOK, map[string]interface{}{"ok": true})
}

func (h *Handler) LeaveEvent(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	userID, ok := middleware.UserIDFromContext(r.Context())
	if !ok {
		logger.Warn("action", "action", "leave_event", "status", "unauthorized")
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	if !h.joinLeaveLimiter.Allow(strconv.FormatInt(userID, 10)) {
		logger.Warn("action", "action", "leave_event", "status", "rate_limited")
		writeError(w, http.StatusTooManyRequests, "rate limit")
		return
	}
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		logger.Warn("action", "action", "leave_event", "status", "invalid_event_id")
		writeError(w, http.StatusBadRequest, "invalid event id")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()

	if err := h.repo.LeaveEvent(ctx, id, userID); err != nil {
		logger.Error("action", "action", "leave_event", "status", "db_error", "event_id", id, "error", err)
		writeError(w, http.StatusInternalServerError, "leave failed")
		return
	}
	logger.Info("action", "action", "leave_event", "status", "success", "event_id", id)
	writeJSON(w, http.StatusOK, map[string]interface{}{"ok": true})
}

func (h *Handler) LikeEvent(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	userID, ok := middleware.UserIDFromContext(r.Context())
	if !ok {
		logger.Warn("action", "action", "like_event", "status", "unauthorized")
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		logger.Warn("action", "action", "like_event", "status", "invalid_event_id")
		writeError(w, http.StatusBadRequest, "invalid event id")
		return
	}
	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	event, err := h.repo.GetEventByID(ctx, id)
	if err != nil {
		logger.Warn("action", "action", "like_event", "status", "not_found", "event_id", id)
		writeError(w, http.StatusNotFound, "event not found")
		return
	}
	if event.IsHidden {
		writeError(w, http.StatusNotFound, "event not found")
		return
	}
	if err := h.repo.LikeEvent(ctx, id, userID); err != nil {
		logger.Error("action", "action", "like_event", "status", "db_error", "event_id", id, "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	count, err := h.repo.CountEventLikes(ctx, id)
	if err != nil {
		logger.Error("action", "action", "like_event", "status", "count_error", "event_id", id, "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	logger.Info("action", "action", "like_event", "status", "success", "event_id", id, "user_id", userID)
	writeJSON(w, http.StatusOK, map[string]interface{}{"ok": true, "likesCount": count, "isLiked": true})
}

func (h *Handler) UnlikeEvent(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	userID, ok := middleware.UserIDFromContext(r.Context())
	if !ok {
		logger.Warn("action", "action", "unlike_event", "status", "unauthorized")
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		logger.Warn("action", "action", "unlike_event", "status", "invalid_event_id")
		writeError(w, http.StatusBadRequest, "invalid event id")
		return
	}
	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	if err := h.repo.UnlikeEvent(ctx, id, userID); err != nil {
		logger.Error("action", "action", "unlike_event", "status", "db_error", "event_id", id, "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	count, err := h.repo.CountEventLikes(ctx, id)
	if err != nil {
		logger.Error("action", "action", "unlike_event", "status", "count_error", "event_id", id, "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	logger.Info("action", "action", "unlike_event", "status", "success", "event_id", id, "user_id", userID)
	writeJSON(w, http.StatusOK, map[string]interface{}{"ok": true, "likesCount": count, "isLiked": false})
}

func (h *Handler) ListEventComments(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	eventID, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		logger.Warn("action", "action", "list_comments", "status", "invalid_event_id")
		writeError(w, http.StatusBadRequest, "invalid event id")
		return
	}
	limit := 50
	offset := 0
	if raw := r.URL.Query().Get("limit"); raw != "" {
		if parsed, err := strconv.Atoi(raw); err == nil && parsed > 0 {
			if parsed > 200 {
				parsed = 200
			}
			limit = parsed
		}
	}
	if raw := r.URL.Query().Get("offset"); raw != "" {
		if parsed, err := strconv.Atoi(raw); err == nil && parsed >= 0 {
			offset = parsed
		}
	}
	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	event, err := h.repo.GetEventByID(ctx, eventID)
	if err != nil || event.IsHidden {
		logger.Warn("action", "action", "list_comments", "status", "not_found", "event_id", eventID)
		writeError(w, http.StatusNotFound, "event not found")
		return
	}
	comments, err := h.repo.ListEventComments(ctx, eventID, limit, offset)
	if err != nil {
		logger.Error("action", "action", "list_comments", "status", "db_error", "event_id", eventID, "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	writeJSON(w, http.StatusOK, comments)
}

func (h *Handler) AddEventComment(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	userID, ok := middleware.UserIDFromContext(r.Context())
	if !ok {
		logger.Warn("action", "action", "add_comment", "status", "unauthorized")
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	eventID, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		logger.Warn("action", "action", "add_comment", "status", "invalid_event_id")
		writeError(w, http.StatusBadRequest, "invalid event id")
		return
	}
	var req commentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		logger.Warn("action", "action", "add_comment", "status", "invalid_json")
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	body := strings.TrimSpace(req.Body)
	if body == "" || utf8.RuneCountInString(body) > maxCommentLength {
		logger.Warn("action", "action", "add_comment", "status", "invalid_body")
		writeError(w, http.StatusBadRequest, "comment length invalid")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	event, err := h.repo.GetEventByID(ctx, eventID)
	if err != nil {
		logger.Warn("action", "action", "add_comment", "status", "not_found", "event_id", eventID)
		writeError(w, http.StatusNotFound, "event not found")
		return
	}
	if event.IsHidden {
		writeError(w, http.StatusNotFound, "event not found")
		return
	}

	comment, err := h.repo.AddEventComment(ctx, eventID, userID, body)
	if err != nil {
		logger.Error("action", "action", "add_comment", "status", "db_error", "event_id", eventID, "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	commentsCount, err := h.repo.CountEventComments(ctx, eventID)
	if err != nil {
		logger.Error("action", "action", "add_comment", "status", "count_error", "event_id", eventID, "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}

	if event.CreatorUserID != userID {
		payload := map[string]interface{}{
			"eventId":       eventID,
			"title":         event.Title,
			"comment":       comment.Body,
			"commenterName": comment.UserName,
		}
		_, _ = h.repo.CreateNotificationJob(ctx, models.NotificationJob{
			UserID:  event.CreatorUserID,
			EventID: &eventID,
			Kind:    "comment_added",
			RunAt:   time.Now(),
			Payload: payload,
			Status:  "pending",
		})
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{"comment": comment, "commentsCount": commentsCount})
	logger.Info("action", "action", "add_comment", "status", "success", "event_id", eventID, "user_id", userID)
}

func (h *Handler) PromoteEvent(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "promote_event"); !ok {
		return
	}

	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		logger.Warn("action", "action", "promote_event", "status", "invalid_event_id")
		writeError(w, http.StatusBadRequest, "invalid event id")
		return
	}

	var req promoteEventRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		logger.Warn("action", "action", "promote_event", "status", "invalid_json")
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}

	if req.DurationMinutes != nil && req.PromotedUntil != nil {
		logger.Warn("action", "action", "promote_event", "status", "conflicting_params")
		writeError(w, http.StatusBadRequest, "provide promotedUntil or durationMinutes")
		return
	}

	var promotedUntil *time.Time
	if req.Clear {
		promotedUntil = nil
	} else if req.DurationMinutes != nil {
		if *req.DurationMinutes <= 0 {
			logger.Warn("action", "action", "promote_event", "status", "invalid_duration")
			writeError(w, http.StatusBadRequest, "durationMinutes must be > 0")
			return
		}
		until := time.Now().Add(time.Duration(*req.DurationMinutes) * time.Minute)
		promotedUntil = &until
	} else if req.PromotedUntil != nil {
		value := strings.TrimSpace(*req.PromotedUntil)
		if value == "" {
			promotedUntil = nil
		} else {
			parsed, err := time.Parse(time.RFC3339, value)
			if err != nil {
				logger.Warn("action", "action", "promote_event", "status", "invalid_promoted_until")
				writeError(w, http.StatusBadRequest, "invalid promotedUntil")
				return
			}
			promotedUntil = &parsed
		}
	} else {
		logger.Warn("action", "action", "promote_event", "status", "missing_payload")
		writeError(w, http.StatusBadRequest, "promote payload required")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()

	if err := h.repo.SetEventPromotedUntil(ctx, id, promotedUntil); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			logger.Warn("action", "action", "promote_event", "status", "not_found", "event_id", id)
			writeError(w, http.StatusNotFound, "event not found")
			return
		}
		logger.Error("action", "action", "promote_event", "status", "db_error", "event_id", id, "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}

	logger.Info("action", "action", "promote_event", "status", "success", "event_id", id)
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func parseLatLng(r *http.Request) (*float64, *float64) {
	q := r.URL.Query()
	latRaw := q.Get("lat")
	lngRaw := q.Get("lng")
	if latRaw == "" || lngRaw == "" {
		return nil, nil
	}
	latVal, err := strconv.ParseFloat(latRaw, 64)
	if err != nil || latVal < -90 || latVal > 90 {
		return nil, nil
	}
	lngVal, err := strconv.ParseFloat(lngRaw, 64)
	if err != nil || lngVal < -180 || lngVal > 180 {
		return nil, nil
	}
	return &latVal, &lngVal
}

func parseRadiusM(r *http.Request) int {
	raw := r.URL.Query().Get("radiusM")
	if raw == "" {
		return 0
	}
	value, err := strconv.Atoi(raw)
	if err != nil || value <= 0 {
		return 0
	}
	return value
}

func publicBaseURL(r *http.Request) string {
	if r == nil {
		return ""
	}
	// Respect reverse proxy headers so generated links point to the public origin.
	host := forwardedHeaderValue(r.Header.Get("X-Forwarded-Host"))
	if host == "" {
		host = strings.TrimSpace(r.Host)
	}
	if host == "" {
		return ""
	}
	proto := forwardedHeaderValue(r.Header.Get("X-Forwarded-Proto"))
	if proto == "" {
		if r.TLS != nil {
			proto = "https"
		} else {
			proto = "http"
		}
	}
	return proto + "://" + host
}

func forwardedHeaderValue(value string) string {
	if value == "" {
		return ""
	}
	if idx := strings.Index(value, ","); idx >= 0 {
		value = value[:idx]
	}
	return strings.TrimSpace(value)
}
