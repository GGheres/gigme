package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	parsercore "gigme/backend/internal/eventparser/core"
	"gigme/backend/internal/geocode"
	"gigme/backend/internal/http/middleware"
	"gigme/backend/internal/models"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
)

const (
	parserImportFallbackLead = time.Hour
	parserImportMinStartLead = 5 * time.Minute
)

type adminParserSourcesResponse struct {
	Items []models.AdminParserSource `json:"items"`
	Total int                        `json:"total"`
}

type adminParsedEventsResponse struct {
	Items []models.AdminParsedEvent `json:"items"`
	Total int                       `json:"total"`
}

type createParserSourceRequest struct {
	SourceType string `json:"sourceType"`
	Input      string `json:"input"`
	Title      string `json:"title"`
	IsActive   *bool  `json:"isActive"`
}

type updateParserSourceRequest struct {
	IsActive *bool `json:"isActive"`
}

type parseInputRequest struct {
	SourceType string `json:"sourceType"`
	Input      string `json:"input"`
}

type parseInputResponse struct {
	Item  *models.AdminParsedEvent  `json:"item,omitempty"`
	Items []models.AdminParsedEvent `json:"items,omitempty"`
	Count int                       `json:"count"`
	Error string                    `json:"error,omitempty"`
}

type geocodeLocationRequest struct {
	Query string `json:"query"`
	Limit int    `json:"limit"`
}

type geocodeLocationResponse struct {
	Items []geocode.Result `json:"items"`
}

type importParsedEventRequest struct {
	Title       *string  `json:"title"`
	Description *string  `json:"description"`
	StartsAt    *string  `json:"startsAt"`
	Lat         *float64 `json:"lat"`
	Lng         *float64 `json:"lng"`
	Address     *string  `json:"addressLabel"`
	Media       []string `json:"media"`
	Links       []string `json:"links"`
	Filters     []string `json:"filters"`
}

func (h *Handler) ListParserSources(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_parser_list_sources"); !ok {
		return
	}
	limit := 50
	offset := 0
	if val := strings.TrimSpace(r.URL.Query().Get("limit")); val != "" {
		if parsed, err := strconv.Atoi(val); err == nil && parsed > 0 && parsed <= 200 {
			limit = parsed
		}
	}
	if val := strings.TrimSpace(r.URL.Query().Get("offset")); val != "" {
		if parsed, err := strconv.Atoi(val); err == nil && parsed >= 0 {
			offset = parsed
		}
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	items, total, err := h.repo.ListAdminParserSources(ctx, limit, offset)
	if err != nil {
		logger.Error("action", "action", "admin_parser_list_sources", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	writeJSON(w, http.StatusOK, adminParserSourcesResponse{Items: items, Total: total})
}

func (h *Handler) CreateParserSource(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_parser_create_source"); !ok {
		return
	}
	adminUserID, ok := middleware.UserIDFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	var req createParserSourceRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	input := strings.TrimSpace(req.Input)
	if input == "" {
		writeError(w, http.StatusBadRequest, "input is required")
		return
	}
	sourceType, err := normalizeParserSourceType(req.SourceType)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	active := true
	if req.IsActive != nil {
		active = *req.IsActive
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	item, err := h.repo.CreateAdminParserSource(ctx, adminUserID, string(sourceType), input, strings.TrimSpace(req.Title), active)
	if err != nil {
		logger.Error("action", "action", "admin_parser_create_source", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	writeJSON(w, http.StatusOK, item)
}

func (h *Handler) UpdateParserSource(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_parser_update_source"); !ok {
		return
	}
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid source id")
		return
	}
	var req updateParserSourceRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	if req.IsActive == nil {
		writeError(w, http.StatusBadRequest, "isActive is required")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	if err := h.repo.SetAdminParserSourceActive(ctx, id, *req.IsActive); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeError(w, http.StatusNotFound, "source not found")
			return
		}
		logger.Error("action", "action", "admin_parser_update_source", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (h *Handler) ParseParserSource(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_parser_parse_source"); !ok {
		return
	}
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid source id")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 90*time.Second)
	defer cancel()
	source, err := h.repo.GetAdminParserSource(ctx, id)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeError(w, http.StatusNotFound, "source not found")
			return
		}
		logger.Error("action", "action", "admin_parser_parse_source", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}

	items, parseErr := h.parseAndStore(ctx, &id, parsercore.SourceType(source.SourceType), source.Input)
	_ = h.repo.TouchAdminParserSourceParsed(ctx, id)
	if parseErr != nil {
		resp := parseInputResponse{Items: items, Count: len(items), Error: parseErr.Error()}
		if len(items) > 0 {
			resp.Item = &items[0]
		}
		writeJSON(w, http.StatusUnprocessableEntity, resp)
		return
	}
	resp := parseInputResponse{Items: items, Count: len(items)}
	if len(items) > 0 {
		resp.Item = &items[0]
	}
	writeJSON(w, http.StatusOK, resp)
}

func (h *Handler) ParseParserInput(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_parser_parse_input"); !ok {
		return
	}
	var req parseInputRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	input := strings.TrimSpace(req.Input)
	if input == "" {
		writeError(w, http.StatusBadRequest, "input is required")
		return
	}
	sourceType, err := normalizeParserSourceType(req.SourceType)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 90*time.Second)
	defer cancel()
	items, parseErr := h.parseAndStore(ctx, nil, sourceType, input)
	if parseErr != nil {
		resp := parseInputResponse{Items: items, Count: len(items), Error: parseErr.Error()}
		if len(items) > 0 {
			resp.Item = &items[0]
		}
		writeJSON(w, http.StatusUnprocessableEntity, resp)
		return
	}
	resp := parseInputResponse{Items: items, Count: len(items)}
	if len(items) > 0 {
		resp.Item = &items[0]
	}
	writeJSON(w, http.StatusOK, resp)
}

func (h *Handler) GeocodeParserLocation(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_parser_geocode"); !ok {
		return
	}
	var req geocodeLocationRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	query := strings.TrimSpace(req.Query)
	if query == "" {
		writeError(w, http.StatusBadRequest, "query is required")
		return
	}
	limit := req.Limit
	if limit <= 0 {
		limit = 1
	}
	if limit > 5 {
		limit = 5
	}
	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()
	items, err := h.geocoder.Search(ctx, query, limit)
	if err != nil {
		logger.Warn("action", "action", "admin_parser_geocode", "status", "geocode_error", "error", err)
		writeError(w, http.StatusBadGateway, "geocoding failed")
		return
	}
	writeJSON(w, http.StatusOK, geocodeLocationResponse{Items: items})
}

func (h *Handler) ListParsedEvents(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_parser_list_events"); !ok {
		return
	}
	limit := 50
	offset := 0
	if val := strings.TrimSpace(r.URL.Query().Get("limit")); val != "" {
		if parsed, err := strconv.Atoi(val); err == nil && parsed > 0 && parsed <= 200 {
			limit = parsed
		}
	}
	if val := strings.TrimSpace(r.URL.Query().Get("offset")); val != "" {
		if parsed, err := strconv.Atoi(val); err == nil && parsed >= 0 {
			offset = parsed
		}
	}
	status := strings.TrimSpace(r.URL.Query().Get("status"))
	var sourceID *int64
	if val := strings.TrimSpace(r.URL.Query().Get("sourceId")); val != "" {
		parsed, err := strconv.ParseInt(val, 10, 64)
		if err != nil {
			writeError(w, http.StatusBadRequest, "invalid sourceId")
			return
		}
		sourceID = &parsed
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	items, total, err := h.repo.ListAdminParsedEvents(ctx, status, sourceID, limit, offset)
	if err != nil {
		logger.Error("action", "action", "admin_parser_list_events", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	writeJSON(w, http.StatusOK, adminParsedEventsResponse{Items: items, Total: total})
}

func (h *Handler) RejectParsedEvent(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_parser_reject_event"); !ok {
		return
	}
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid parsed event id")
		return
	}
	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	if err := h.repo.RejectAdminParsedEvent(ctx, id); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeError(w, http.StatusNotFound, "parsed event not found")
			return
		}
		logger.Error("action", "action", "admin_parser_reject_event", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (h *Handler) DeleteParsedEvent(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_parser_delete_event"); !ok {
		return
	}
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid parsed event id")
		return
	}
	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	if err := h.repo.DeleteAdminParsedEvent(ctx, id); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeError(w, http.StatusNotFound, "parsed event not found")
			return
		}
		logger.Error("action", "action", "admin_parser_delete_event", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (h *Handler) ImportParsedEvent(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_parser_import_event"); !ok {
		return
	}
	adminUserID, ok := middleware.UserIDFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid parsed event id")
		return
	}
	var req importParsedEventRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 15*time.Second)
	defer cancel()
	parsedEvent, err := h.repo.GetAdminParsedEvent(ctx, id)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeError(w, http.StatusNotFound, "parsed event not found")
			return
		}
		logger.Error("action", "action", "admin_parser_import_event", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	if parsedEvent.Status == "imported" {
		writeError(w, http.StatusConflict, "parsed event already imported")
		return
	}
	if req.Lat == nil || req.Lng == nil {
		writeError(w, http.StatusBadRequest, "lat and lng are required")
		return
	}
	if *req.Lat < -90 || *req.Lat > 90 || *req.Lng < -180 || *req.Lng > 180 {
		writeError(w, http.StatusBadRequest, "invalid coordinates")
		return
	}

	title := strings.TrimSpace(firstString(req.Title, parsedEvent.Name))
	if title == "" {
		title = "Imported event"
	}
	description := strings.TrimSpace(firstString(req.Description, parsedEvent.Description))
	if description == "" {
		description = "Imported from parser"
	}

	var startsAt time.Time
	var startsAtExplicit bool
	nowUTC := time.Now().UTC()
	if req.StartsAt != nil && strings.TrimSpace(*req.StartsAt) != "" {
		startsAtExplicit = true
		startsAt, err = parseEventTime(*req.StartsAt)
		if err != nil {
			writeError(w, http.StatusBadRequest, "invalid startsAt")
			return
		}
	} else if parsedEvent.DateTime != nil {
		startsAt = *parsedEvent.DateTime
	} else {
		startsAt = nowUTC.Add(parserImportFallbackLead)
	}
	if !startsAtExplicit {
		normalized, adjusted := normalizeImportedStartsAt(startsAt, nowUTC)
		if adjusted {
			logger.Info(
				"action", "action", "admin_parser_import_event",
				"status", "starts_at_adjusted",
				"parsed_event_id", id,
				"from", startsAt.UTC().Format(time.RFC3339),
				"to", normalized.Format(time.RFC3339),
			)
		}
		startsAt = normalized
	}

	address := strings.TrimSpace(firstString(req.Address, parsedEvent.Location))
	filters, err := normalizeEventFilters(req.Filters, maxEventFilters)
	if err != nil {
		if errors.Is(err, errInvalidFilters) {
			writeError(w, http.StatusBadRequest, "invalid filters")
			return
		}
		if errors.Is(err, errTooManyFilters) {
			writeError(w, http.StatusBadRequest, "too many filters")
			return
		}
		writeError(w, http.StatusBadRequest, "invalid filters")
		return
	}

	event := models.Event{
		CreatorUserID: adminUserID,
		Title:         title,
		Description:   description,
		StartsAt:      startsAt.UTC(),
		Lat:           *req.Lat,
		Lng:           *req.Lng,
		AddressLabel:  address,
		Filters:       filters,
		Links:         normalizeImportLinks(req.Links, parsedEvent.Links, 20),
	}
	media := normalizeImportMedia(req.Media, parsedEvent.Links, 5)
	eventID, err := h.repo.ImportAdminParsedEvent(ctx, id, adminUserID, event, media)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeError(w, http.StatusNotFound, "parsed event not found")
			return
		}
		logger.Error("action", "action", "admin_parser_import_event", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"ok":       true,
		"eventId":  eventID,
		"startsAt": event.StartsAt,
	})
}

func (h *Handler) parseAndStore(ctx context.Context, sourceID *int64, sourceType parsercore.SourceType, input string) ([]models.AdminParsedEvent, error) {
	if sourceType == "" {
		sourceType = parsercore.SourceAuto
	}
	events, err := h.eventParser.ParseEventsWithSource(ctx, input, sourceType)
	if err != nil {
		item, saveErr := h.repo.CreateAdminParsedEvent(
			ctx,
			sourceID,
			string(sourceType),
			input,
			"",
			nil,
			"",
			"",
			nil,
			"error",
			err.Error(),
		)
		if saveErr != nil {
			return nil, fmt.Errorf("parse error: %w; save error: %v", err, saveErr)
		}
		return []models.AdminParsedEvent{item}, err
	}
	if len(events) == 0 {
		item, saveErr := h.repo.CreateAdminParsedEvent(
			ctx,
			sourceID,
			string(sourceType),
			input,
			"",
			nil,
			"",
			"",
			nil,
			"error",
			"no events parsed",
		)
		if saveErr != nil {
			return nil, saveErr
		}
		return []models.AdminParsedEvent{item}, fmt.Errorf("no events parsed")
	}
	out := make([]models.AdminParsedEvent, 0, len(events))
	for _, eventData := range events {
		if eventData == nil {
			continue
		}
		item, saveErr := h.repo.CreateAdminParsedEvent(
			ctx,
			sourceID,
			string(sourceType),
			input,
			eventData.Name,
			eventData.DateTime,
			eventData.Location,
			eventData.Description,
			eventData.Links,
			"pending",
			"",
		)
		if saveErr != nil {
			return out, saveErr
		}
		out = append(out, item)
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("no events parsed")
	}
	return out, nil
}

func normalizeParserSourceType(raw string) (parsercore.SourceType, error) {
	sourceType := parsercore.SourceType(strings.ToLower(strings.TrimSpace(raw)))
	if sourceType == "" {
		sourceType = parsercore.SourceAuto
	}
	if !sourceType.Valid() {
		return "", fmt.Errorf("invalid sourceType")
	}
	return sourceType, nil
}

func firstString(preferred *string, fallback string) string {
	if preferred != nil {
		return strings.TrimSpace(*preferred)
	}
	return strings.TrimSpace(fallback)
}

func parseEventTime(raw string) (time.Time, error) {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return time.Time{}, fmt.Errorf("empty time")
	}
	if ts, err := time.Parse(time.RFC3339, trimmed); err == nil {
		return ts, nil
	}
	if ts, err := time.ParseInLocation("2006-01-02T15:04", trimmed, time.UTC); err == nil {
		return ts, nil
	}
	return time.Time{}, fmt.Errorf("invalid time")
}

func normalizeImportedStartsAt(startsAt time.Time, now time.Time) (time.Time, bool) {
	base := startsAt.UTC()
	if base.IsZero() {
		return now.UTC().Add(parserImportFallbackLead), true
	}
	minAllowed := now.UTC().Add(parserImportMinStartLead)
	if base.Before(minAllowed) {
		return now.UTC().Add(parserImportFallbackLead), true
	}
	return base, false
}

func normalizeImportMedia(explicit []string, links []string, limit int) []string {
	candidates := explicit
	if len(candidates) == 0 {
		candidates = extractImageLinks(links)
	}
	seen := make(map[string]struct{}, len(candidates))
	out := make([]string, 0, len(candidates))
	for _, raw := range candidates {
		link := strings.TrimSpace(raw)
		if link == "" {
			continue
		}
		if _, exists := seen[link]; exists {
			continue
		}
		seen[link] = struct{}{}
		out = append(out, link)
		if limit > 0 && len(out) >= limit {
			break
		}
	}
	return out
}

func extractImageLinks(links []string) []string {
	out := make([]string, 0, len(links))
	for _, link := range links {
		l := strings.ToLower(strings.TrimSpace(link))
		if l == "" {
			continue
		}
		if strings.Contains(l, "image") ||
			strings.HasSuffix(l, ".jpg") ||
			strings.HasSuffix(l, ".jpeg") ||
			strings.HasSuffix(l, ".png") ||
			strings.HasSuffix(l, ".webp") ||
			strings.HasSuffix(l, ".gif") {
			out = append(out, link)
		}
	}
	return out
}

func normalizeImportLinks(explicit []string, parsed []string, limit int) []string {
	candidates := explicit
	if len(candidates) == 0 {
		candidates = parsed
	}
	images := make(map[string]struct{})
	for _, img := range extractImageLinks(candidates) {
		images[strings.ToLower(strings.TrimSpace(img))] = struct{}{}
	}
	seen := make(map[string]struct{}, len(candidates))
	out := make([]string, 0, len(candidates))
	for _, raw := range candidates {
		link := strings.TrimSpace(raw)
		if link == "" {
			continue
		}
		key := strings.ToLower(link)
		if _, isImage := images[key]; isImage {
			continue
		}
		if _, exists := seen[key]; exists {
			continue
		}
		seen[key] = struct{}{}
		out = append(out, link)
		if limit > 0 && len(out) >= limit {
			break
		}
	}
	return out
}
