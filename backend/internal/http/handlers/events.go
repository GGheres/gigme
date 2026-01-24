package handlers

import (
	"encoding/json"
	"net/http"
	"strconv"
	"time"

	"gigme/backend/internal/http/middleware"
	"gigme/backend/internal/models"

	"github.com/go-chi/chi/v5"
)

type createEventRequest struct {
	Title       string   `json:"title"`
	Description string   `json:"description"`
	StartsAt    string   `json:"startsAt"`
	EndsAt      *string  `json:"endsAt"`
	Lat         float64  `json:"lat"`
	Lng         float64  `json:"lng"`
	Capacity    *int     `json:"capacity"`
	Media       []string `json:"media"`
	Address     string   `json:"addressLabel"`
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

	if len(req.Title) == 0 || len(req.Title) > 80 {
		logger.Warn("action", "action", "create_event", "status", "invalid_title")
		writeError(w, http.StatusBadRequest, "title length invalid")
		return
	}
	if len(req.Description) == 0 || len(req.Description) > 1000 {
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
	if count >= 5 {
		logger.Warn("action", "action", "create_event", "status", "rate_limited")
		writeError(w, http.StatusTooManyRequests, "event create limit reached")
		return
	}

	eventID, err := h.repo.CreateEventWithMedia(ctx, models.Event{
		CreatorUserID: userID,
		Title:         req.Title,
		Description:   req.Description,
		StartsAt:      startsAt,
		EndsAt:        endsAt,
		Lat:           req.Lat,
		Lng:           req.Lng,
		Capacity:      req.Capacity,
		AddressLabel:  req.Address,
	}, req.Media)
	if err != nil {
		logger.Error("action", "action", "create_event", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "failed to create event")
		return
	}

	_ = h.repo.JoinEvent(ctx, eventID, userID)

	nearbyCutoff := time.Now().Add(-2 * time.Hour)
	nearbyUserIDs, err := h.repo.GetNearbyUserIDs(ctx, req.Lat, req.Lng, 100000, userID, &nearbyCutoff, 500)
	if err == nil {
		for _, nearbyUserID := range nearbyUserIDs {
			_, _ = h.repo.CreateNotificationJob(ctx, models.NotificationJob{
				UserID:  nearbyUserID,
				EventID: &eventID,
				Kind:    "event_nearby",
				RunAt:   time.Now(),
				Payload: map[string]interface{}{"eventId": eventID, "title": req.Title},
				Status:  "pending",
			})
		}
	}

	_, _ = h.repo.CreateNotificationJob(ctx, models.NotificationJob{
		UserID:  userID,
		EventID: &eventID,
		Kind:    "event_created",
		RunAt:   time.Now(),
		Payload: map[string]interface{}{"eventId": eventID, "title": req.Title},
		Status:  "pending",
	})

	title := req.Title
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
		"title", req.Title,
		"starts_at", startsAt,
		"ends_at", endsAt,
		"lat", req.Lat,
		"lng", req.Lng,
		"capacity", req.Capacity,
		"media_count", len(req.Media),
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

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	markers, err := h.repo.GetEventMarkers(ctx, from, to, lat, lng, radius)
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

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	items, err := h.repo.GetFeed(ctx, limit, offset, lat, lng, radius)
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

func (h *Handler) PromoteEvent(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	logger.Warn("action", "action", "promote_event", "status", "not_implemented")
	writeError(w, http.StatusNotImplemented, "not implemented")
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
