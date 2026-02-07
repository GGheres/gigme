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
	Item  models.AdminParsedEvent `json:"item"`
	Error string                  `json:"error,omitempty"`
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

	ctx, cancel := context.WithTimeout(r.Context(), 20*time.Second)
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

	item, parseErr := h.parseAndStore(ctx, &id, parsercore.SourceType(source.SourceType), source.Input)
	_ = h.repo.TouchAdminParserSourceParsed(ctx, id)
	if parseErr != nil {
		writeJSON(w, http.StatusUnprocessableEntity, parseInputResponse{Item: item, Error: parseErr.Error()})
		return
	}
	writeJSON(w, http.StatusOK, parseInputResponse{Item: item})
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

	ctx, cancel := context.WithTimeout(r.Context(), 20*time.Second)
	defer cancel()
	item, parseErr := h.parseAndStore(ctx, nil, sourceType, input)
	if parseErr != nil {
		writeJSON(w, http.StatusUnprocessableEntity, parseInputResponse{Item: item, Error: parseErr.Error()})
		return
	}
	writeJSON(w, http.StatusOK, parseInputResponse{Item: item})
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
	if len(req.Media) > 5 {
		writeError(w, http.StatusBadRequest, "media limit exceeded")
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
	if req.StartsAt != nil && strings.TrimSpace(*req.StartsAt) != "" {
		startsAt, err = parseEventTime(*req.StartsAt)
		if err != nil {
			writeError(w, http.StatusBadRequest, "invalid startsAt")
			return
		}
	} else if parsedEvent.DateTime != nil {
		startsAt = *parsedEvent.DateTime
	} else {
		writeError(w, http.StatusBadRequest, "startsAt is required when parsed date is missing")
		return
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
	}
	eventID, err := h.repo.ImportAdminParsedEvent(ctx, id, adminUserID, event, req.Media)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeError(w, http.StatusNotFound, "parsed event not found")
			return
		}
		logger.Error("action", "action", "admin_parser_import_event", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"ok": true, "eventId": eventID})
}

func (h *Handler) parseAndStore(ctx context.Context, sourceID *int64, sourceType parsercore.SourceType, input string) (models.AdminParsedEvent, error) {
	if sourceType == "" {
		sourceType = parsercore.SourceAuto
	}
	eventData, err := h.eventParser.ParseEventWithSource(ctx, input, sourceType)
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
			return models.AdminParsedEvent{}, fmt.Errorf("parse error: %w; save error: %v", err, saveErr)
		}
		return item, err
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
		return models.AdminParsedEvent{}, saveErr
	}
	return item, nil
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
