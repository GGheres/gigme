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
	userID, ok := middleware.UserIDFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	var req createEventRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}

	if len(req.Title) == 0 || len(req.Title) > 80 {
		writeError(w, http.StatusBadRequest, "title length invalid")
		return
	}
	if len(req.Description) == 0 || len(req.Description) > 1000 {
		writeError(w, http.StatusBadRequest, "description length invalid")
		return
	}
	if req.Lat < -90 || req.Lat > 90 || req.Lng < -180 || req.Lng > 180 {
		writeError(w, http.StatusBadRequest, "invalid coordinates")
		return
	}
	if req.Capacity != nil && *req.Capacity <= 0 {
		writeError(w, http.StatusBadRequest, "capacity must be > 0")
		return
	}
	if len(req.Media) > 5 {
		writeError(w, http.StatusBadRequest, "media limit exceeded")
		return
	}

	startsAt, err := time.Parse(time.RFC3339, req.StartsAt)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid startsAt")
		return
	}
	var endsAt *time.Time
	if req.EndsAt != nil && *req.EndsAt != "" {
		parsed, err := time.Parse(time.RFC3339, *req.EndsAt)
		if err != nil {
			writeError(w, http.StatusBadRequest, "invalid endsAt")
			return
		}
		if parsed.Before(startsAt) {
			writeError(w, http.StatusBadRequest, "endsAt before startsAt")
			return
		}
		endsAt = &parsed
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()

	count, err := h.repo.CountUserEventsLastHour(ctx, userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "rate limit check failed")
		return
	}
	if count >= 3 {
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
		writeError(w, http.StatusInternalServerError, "failed to create event")
		return
	}

	_ = h.repo.JoinEvent(ctx, eventID, userID)

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

	writeJSON(w, http.StatusOK, map[string]interface{}{"eventId": eventID})
}

func (h *Handler) NearbyEvents(w http.ResponseWriter, r *http.Request) {
	lat, err := strconv.ParseFloat(r.URL.Query().Get("lat"), 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid lat")
		return
	}
	lng, err := strconv.ParseFloat(r.URL.Query().Get("lng"), 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid lng")
		return
	}
	radius := 5000
	if v := r.URL.Query().Get("radiusM"); v != "" {
		if parsed, err := strconv.Atoi(v); err == nil && parsed > 0 {
			radius = parsed
		}
	}
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

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	markers, err := h.repo.GetEventMarkers(ctx, lat, lng, radius, from, to)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	writeJSON(w, http.StatusOK, markers)
}

func (h *Handler) Feed(w http.ResponseWriter, r *http.Request) {
	lat, err := strconv.ParseFloat(r.URL.Query().Get("lat"), 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid lat")
		return
	}
	lng, err := strconv.ParseFloat(r.URL.Query().Get("lng"), 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid lng")
		return
	}
	radius := 5000
	if v := r.URL.Query().Get("radiusM"); v != "" {
		if parsed, err := strconv.Atoi(v); err == nil && parsed > 0 {
			radius = parsed
		}
	}
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

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	items, err := h.repo.GetFeed(ctx, lat, lng, radius, limit, offset)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	writeJSON(w, http.StatusOK, items)
}

func (h *Handler) GetEvent(w http.ResponseWriter, r *http.Request) {
	eventID, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid event id")
		return
	}
	userID, _ := middleware.UserIDFromContext(r.Context())

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()

	event, err := h.repo.GetEventByID(ctx, eventID)
	if err != nil {
		writeError(w, http.StatusNotFound, "event not found")
		return
	}
	if event.IsHidden {
		writeError(w, http.StatusNotFound, "event not found")
		return
	}

	participants, err := h.repo.GetParticipantsPreview(ctx, eventID, 10)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	media, err := h.repo.ListEventMedia(ctx, eventID)
	if err != nil {
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
}

func (h *Handler) JoinEvent(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.UserIDFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	if !h.joinLeaveLimiter.Allow(strconv.FormatInt(userID, 10)) {
		writeError(w, http.StatusTooManyRequests, "rate limit")
		return
	}
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid event id")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()

	cap, err := h.repo.GetEventCapacity(ctx, id)
	if err != nil {
		writeError(w, http.StatusNotFound, "event not found")
		return
	}
	if cap != nil {
		count, err := h.repo.CountParticipants(ctx, id)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "db error")
			return
		}
		if count >= *cap {
			writeError(w, http.StatusBadRequest, "event capacity full")
			return
		}
	}

	if err := h.repo.JoinEvent(ctx, id, userID); err != nil {
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

	writeJSON(w, http.StatusOK, map[string]interface{}{"ok": true})
}

func (h *Handler) LeaveEvent(w http.ResponseWriter, r *http.Request) {
	userID, ok := middleware.UserIDFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	if !h.joinLeaveLimiter.Allow(strconv.FormatInt(userID, 10)) {
		writeError(w, http.StatusTooManyRequests, "rate limit")
		return
	}
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid event id")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()

	if err := h.repo.LeaveEvent(ctx, id, userID); err != nil {
		writeError(w, http.StatusInternalServerError, "leave failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"ok": true})
}

func (h *Handler) PromoteEvent(w http.ResponseWriter, r *http.Request) {
	writeError(w, http.StatusNotImplemented, "not implemented")
}
