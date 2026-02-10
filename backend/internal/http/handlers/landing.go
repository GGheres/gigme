package handlers

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"strings"

	"gigme/backend/internal/http/middleware"
	"gigme/backend/internal/models"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
)

type landingEventsResponse struct {
	Items []landingEventItem `json:"items"`
	Total int                `json:"total"`
}

type landingEventItem struct {
	ID                int64   `json:"id"`
	Title             string  `json:"title"`
	Description       string  `json:"description"`
	StartsAt          string  `json:"startsAt"`
	EndsAt            *string `json:"endsAt,omitempty"`
	Lat               float64 `json:"lat"`
	Lng               float64 `json:"lng"`
	AddressLabel      string  `json:"addressLabel,omitempty"`
	CreatorName       string  `json:"creatorName,omitempty"`
	ParticipantsCount int     `json:"participantsCount"`
	ThumbnailURL      string  `json:"thumbnailUrl,omitempty"`
	TicketURL         string  `json:"ticketUrl"`
	AppURL            string  `json:"appUrl"`
}

type setLandingPublishRequest struct {
	Published *bool `json:"published"`
}

type landingContentResponse struct {
	HeroEyebrow         string `json:"heroEyebrow"`
	HeroTitle           string `json:"heroTitle"`
	HeroDescription     string `json:"heroDescription"`
	HeroPrimaryCTALabel string `json:"heroPrimaryCtaLabel"`
	AboutTitle          string `json:"aboutTitle"`
	AboutDescription    string `json:"aboutDescription"`
	PartnersTitle       string `json:"partnersTitle"`
	PartnersDescription string `json:"partnersDescription"`
	FooterText          string `json:"footerText"`
}

type upsertLandingContentRequest struct {
	HeroEyebrow         *string `json:"heroEyebrow"`
	HeroTitle           *string `json:"heroTitle"`
	HeroDescription     *string `json:"heroDescription"`
	HeroPrimaryCTALabel *string `json:"heroPrimaryCtaLabel"`
	AboutTitle          *string `json:"aboutTitle"`
	AboutDescription    *string `json:"aboutDescription"`
	PartnersTitle       *string `json:"partnersTitle"`
	PartnersDescription *string `json:"partnersDescription"`
	FooterText          *string `json:"footerText"`
}

const (
	landingDefaultHeroEyebrow         = "SPACEFESTIVAL"
	landingDefaultHeroTitle           = "Spacefestival 2026"
	landingDefaultHeroDescription     = "Три экрана музыки, перформансов и нетворкинга. Лови билет, открывай Space App и следи за обновлениями в реальном времени."
	landingDefaultHeroPrimaryCTALabel = "Купить Билет"
	landingDefaultAboutTitle          = "О мероприятии"
	landingDefaultAboutDescription    = "О мероприятии: сеты артистов, иммерсивные зоны, локальные бренды и серия партнерских активностей. Вся программа обновляется на лендинге."
	landingDefaultPartnersTitle       = "Партнеры и контакты"
	landingDefaultPartnersDescription = "Партнерская сетка формируется. Следите за новыми анонсами."
	landingDefaultFooterText          = "SPACE"
)

func (h *Handler) LandingEvents(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)

	limit := 50
	offset := 0
	if raw := strings.TrimSpace(r.URL.Query().Get("limit")); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil || parsed <= 0 || parsed > 200 {
			writeError(w, http.StatusBadRequest, "invalid limit")
			return
		}
		limit = parsed
	}
	if raw := strings.TrimSpace(r.URL.Query().Get("offset")); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil || parsed < 0 {
			writeError(w, http.StatusBadRequest, "invalid offset")
			return
		}
		offset = parsed
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()

	items, total, err := h.repo.ListLandingEvents(ctx, limit, offset)
	if err != nil {
		logger.Error("action", "action", "landing_events", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}

	baseURL := strings.TrimSpace(h.cfg.BaseURL)
	if baseURL == "" {
		baseURL = publicBaseURL(r)
	}
	responseItems := make([]landingEventItem, 0, len(items))
	for _, item := range items {
		var endsAt *string
		if item.EndsAt != nil {
			value := item.EndsAt.UTC().Format(timeFormatRFC3339Milli)
			endsAt = &value
		}

		appURL := buildLandingAppURL(baseURL, item.ID, item.AccessKey)
		responseItems = append(responseItems, landingEventItem{
			ID:                item.ID,
			Title:             item.Title,
			Description:       item.Description,
			StartsAt:          item.StartsAt.UTC().Format(timeFormatRFC3339Milli),
			EndsAt:            endsAt,
			Lat:               item.Lat,
			Lng:               item.Lng,
			AddressLabel:      item.AddressLabel,
			CreatorName:       item.CreatorName,
			ParticipantsCount: item.Participants,
			ThumbnailURL:      item.ThumbnailURL,
			TicketURL:         buildLandingTicketURL(h.cfg.TelegramUser, item.ID, item.AccessKey, appURL),
			AppURL:            appURL,
		})
	}

	logger.Info("action", "action", "landing_events", "status", "success", "count", len(responseItems))
	writeJSON(w, http.StatusOK, landingEventsResponse{
		Items: responseItems,
		Total: total,
	})
}

func (h *Handler) LandingContent(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()

	content, err := h.repo.GetLandingContent(ctx)
	if err != nil {
		logger.Error("action", "action", "landing_content_get", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	writeJSON(w, http.StatusOK, landingContentToResponse(content))
}

func (h *Handler) UpsertLandingContent(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_upsert_landing_content"); !ok {
		return
	}

	adminUserID, ok := middleware.UserIDFromContext(r.Context())
	if !ok || adminUserID <= 0 {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	var req upsertLandingContentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		logger.Warn("action", "action", "admin_upsert_landing_content", "status", "invalid_json")
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	if !req.hasAny() {
		writeError(w, http.StatusBadRequest, "at least one field is required")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()

	current, err := h.repo.GetLandingContent(ctx)
	if err != nil {
		logger.Error("action", "action", "admin_upsert_landing_content", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}

	merged := mergeLandingContent(current, req)
	merged.UpdatedBy = &adminUserID

	if err := validateLandingContent(merged); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	if err := h.repo.UpsertLandingContent(ctx, merged); err != nil {
		logger.Error("action", "action", "admin_upsert_landing_content", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"ok":      true,
		"content": landingContentToResponse(merged),
	})
}

func (h *Handler) SetEventLandingPublished(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_set_landing_published"); !ok {
		return
	}

	eventID, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		logger.Warn("action", "action", "admin_set_landing_published", "status", "invalid_event_id")
		writeError(w, http.StatusBadRequest, "invalid event id")
		return
	}

	var req setLandingPublishRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		logger.Warn("action", "action", "admin_set_landing_published", "status", "invalid_json")
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	if req.Published == nil {
		logger.Warn("action", "action", "admin_set_landing_published", "status", "missing_published")
		writeError(w, http.StatusBadRequest, "published is required")
		return
	}
	published := *req.Published

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()

	if published {
		event, err := h.repo.GetEventByID(ctx, eventID)
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				logger.Warn("action", "action", "admin_set_landing_published", "status", "not_found", "event_id", eventID)
				writeError(w, http.StatusNotFound, "event not found")
				return
			}
			logger.Error("action", "action", "admin_set_landing_published", "status", "db_error", "event_id", eventID, "error", err)
			writeError(w, http.StatusInternalServerError, "db error")
			return
		}
		if event.IsHidden {
			writeError(w, http.StatusBadRequest, "hidden event can't be published on landing")
			return
		}
		if event.IsPrivate {
			writeError(w, http.StatusBadRequest, "private event can't be published on landing")
			return
		}
	}

	if err := h.repo.SetEventLandingPublished(ctx, eventID, published); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			logger.Warn("action", "action", "admin_set_landing_published", "status", "not_found", "event_id", eventID)
			writeError(w, http.StatusNotFound, "event not found")
			return
		}
		logger.Error("action", "action", "admin_set_landing_published", "status", "db_error", "event_id", eventID, "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}

	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func buildLandingAppURL(baseURL string, eventID int64, eventKey string) string {
	query := url.Values{
		"eventId": {strconv.FormatInt(eventID, 10)},
	}
	if key := sanitizeLandingKey(eventKey); key != "" {
		query.Set("eventKey", key)
	}

	fallback := "/space_app?" + query.Encode()
	base := strings.TrimSpace(baseURL)
	if base == "" {
		return fallback
	}

	parsed, err := url.Parse(base)
	if err != nil || parsed.Scheme == "" || parsed.Host == "" {
		return fallback
	}
	parsed.Path = "/space_app"
	parsed.RawQuery = query.Encode()
	parsed.Fragment = ""
	return parsed.String()
}

func buildLandingTicketURL(botUsername string, eventID int64, eventKey string, fallbackAppURL string) string {
	username := strings.TrimPrefix(strings.TrimSpace(botUsername), "@")
	if username == "" {
		return fallbackAppURL
	}
	startParam := buildLandingStartParam(eventID, sanitizeLandingKey(eventKey))
	return fmt.Sprintf("https://t.me/%s?startapp=%s", username, url.QueryEscape(startParam))
}

func buildLandingStartParam(eventID int64, eventKey string) string {
	if eventKey == "" {
		return fmt.Sprintf("e_%d", eventID)
	}
	return fmt.Sprintf("e_%d_%s", eventID, eventKey)
}

func sanitizeLandingKey(raw string) string {
	value := strings.TrimSpace(raw)
	if value == "" || len(value) > 64 {
		return ""
	}
	var b strings.Builder
	b.Grow(len(value))
	for _, r := range value {
		if (r >= 'a' && r <= 'z') ||
			(r >= 'A' && r <= 'Z') ||
			(r >= '0' && r <= '9') ||
			r == '-' || r == '_' {
			b.WriteRune(r)
		}
	}
	return b.String()
}

func (req upsertLandingContentRequest) hasAny() bool {
	return req.HeroEyebrow != nil ||
		req.HeroTitle != nil ||
		req.HeroDescription != nil ||
		req.HeroPrimaryCTALabel != nil ||
		req.AboutTitle != nil ||
		req.AboutDescription != nil ||
		req.PartnersTitle != nil ||
		req.PartnersDescription != nil ||
		req.FooterText != nil
}

func mergeLandingContent(current models.LandingContent, req upsertLandingContentRequest) models.LandingContent {
	out := current
	if req.HeroEyebrow != nil {
		out.HeroEyebrow = strings.TrimSpace(*req.HeroEyebrow)
	}
	if req.HeroTitle != nil {
		out.HeroTitle = strings.TrimSpace(*req.HeroTitle)
	}
	if req.HeroDescription != nil {
		out.HeroDescription = strings.TrimSpace(*req.HeroDescription)
	}
	if req.HeroPrimaryCTALabel != nil {
		out.HeroPrimaryCTALabel = strings.TrimSpace(*req.HeroPrimaryCTALabel)
	}
	if req.AboutTitle != nil {
		out.AboutTitle = strings.TrimSpace(*req.AboutTitle)
	}
	if req.AboutDescription != nil {
		out.AboutDescription = strings.TrimSpace(*req.AboutDescription)
	}
	if req.PartnersTitle != nil {
		out.PartnersTitle = strings.TrimSpace(*req.PartnersTitle)
	}
	if req.PartnersDescription != nil {
		out.PartnersDescription = strings.TrimSpace(*req.PartnersDescription)
	}
	if req.FooterText != nil {
		out.FooterText = strings.TrimSpace(*req.FooterText)
	}
	return out
}

func landingContentToResponse(content models.LandingContent) landingContentResponse {
	return landingContentResponse{
		HeroEyebrow:         firstNonEmpty(content.HeroEyebrow, landingDefaultHeroEyebrow),
		HeroTitle:           firstNonEmpty(content.HeroTitle, landingDefaultHeroTitle),
		HeroDescription:     firstNonEmpty(content.HeroDescription, landingDefaultHeroDescription),
		HeroPrimaryCTALabel: firstNonEmpty(content.HeroPrimaryCTALabel, landingDefaultHeroPrimaryCTALabel),
		AboutTitle:          firstNonEmpty(content.AboutTitle, landingDefaultAboutTitle),
		AboutDescription:    firstNonEmpty(content.AboutDescription, landingDefaultAboutDescription),
		PartnersTitle:       firstNonEmpty(content.PartnersTitle, landingDefaultPartnersTitle),
		PartnersDescription: firstNonEmpty(content.PartnersDescription, landingDefaultPartnersDescription),
		FooterText:          firstNonEmpty(content.FooterText, landingDefaultFooterText),
	}
}

func firstNonEmpty(raw string, fallback string) string {
	value := strings.TrimSpace(raw)
	if value == "" {
		return fallback
	}
	return value
}

func validateLandingContent(content models.LandingContent) error {
	type limit struct {
		field string
		value string
		max   int
	}
	limits := []limit{
		{field: "heroEyebrow", value: content.HeroEyebrow, max: 80},
		{field: "heroTitle", value: content.HeroTitle, max: 140},
		{field: "heroDescription", value: content.HeroDescription, max: 1800},
		{field: "heroPrimaryCtaLabel", value: content.HeroPrimaryCTALabel, max: 80},
		{field: "aboutTitle", value: content.AboutTitle, max: 140},
		{field: "aboutDescription", value: content.AboutDescription, max: 2400},
		{field: "partnersTitle", value: content.PartnersTitle, max: 140},
		{field: "partnersDescription", value: content.PartnersDescription, max: 1800},
		{field: "footerText", value: content.FooterText, max: 260},
	}
	for _, item := range limits {
		if len([]rune(strings.TrimSpace(item.value))) > item.max {
			return fmt.Errorf("%s is too long (max %d chars)", item.field, item.max)
		}
	}
	return nil
}

const timeFormatRFC3339Milli = "2006-01-02T15:04:05.000Z07:00"
