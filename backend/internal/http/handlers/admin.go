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
