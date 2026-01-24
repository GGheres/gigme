package handlers

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"strings"
	"time"
)

type clientLogEvent struct {
	Level     string                 `json:"level"`
	Message   string                 `json:"message"`
	Meta      map[string]interface{} `json:"meta"`
	Timestamp string                 `json:"timestamp"`
	URL       string                 `json:"url"`
	UserAgent string                 `json:"userAgent"`
}

type clientLogRequest struct {
	Events    []clientLogEvent       `json:"events"`
	Level     string                 `json:"level"`
	Message   string                 `json:"message"`
	Meta      map[string]interface{} `json:"meta"`
	Timestamp string                 `json:"timestamp"`
	URL       string                 `json:"url"`
	UserAgent string                 `json:"userAgent"`
}

var suppressedClientMessages = map[string]struct{}{
	"api_error":          {},
	"api_response_error": {},
	"feed_load_error":    {},
	"geolocation_error":  {},
}

func (h *Handler) ClientLogs(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	var req clientLogRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		logger.Warn("client_log", "status", "invalid_json")
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}

	events := req.Events
	if len(events) == 0 && req.Message != "" {
		events = []clientLogEvent{{
			Level:     req.Level,
			Message:   req.Message,
			Meta:      req.Meta,
			Timestamp: req.Timestamp,
			URL:       req.URL,
			UserAgent: req.UserAgent,
		}}
	}

	if len(events) == 0 {
		logger.Warn("client_log", "status", "empty_payload")
		writeError(w, http.StatusBadRequest, "empty payload")
		return
	}

	if len(events) > 100 {
		logger.Warn("client_log", "status", "too_many_events", "count", len(events))
		writeError(w, http.StatusBadRequest, "too many events")
		return
	}

	for _, event := range events {
		if shouldSuppressClientEvent(event) {
			continue
		}
		logClientEvent(logger, r, event)
	}

	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func shouldSuppressClientEvent(event clientLogEvent) bool {
	if event.Message == "" {
		return false
	}
	message := strings.ToLower(strings.TrimSpace(event.Message))
	_, ok := suppressedClientMessages[message]
	return ok
}

func logClientEvent(logger *slog.Logger, r *http.Request, event clientLogEvent) {
	if logger == nil {
		logger = slog.Default()
	}

	level := strings.ToLower(strings.TrimSpace(event.Level))
	if level == "" {
		level = "info"
	}

	attrs := []any{
		"source", "client",
		"message", event.Message,
	}
	if event.Timestamp != "" {
		attrs = append(attrs, "timestamp", event.Timestamp)
	} else {
		attrs = append(attrs, "timestamp", time.Now().Format(time.RFC3339))
	}
	if event.URL != "" {
		attrs = append(attrs, "url", event.URL)
	}
	if event.UserAgent != "" {
		attrs = append(attrs, "user_agent", event.UserAgent)
	}
	if event.Meta != nil && len(event.Meta) > 0 {
		attrs = append(attrs, "meta", event.Meta)
	}
	if r != nil && r.RemoteAddr != "" {
		attrs = append(attrs, "ip", r.RemoteAddr)
	}

	switch level {
	case "debug":
		logger.Debug("client_log", attrs...)
	case "warn", "warning":
		logger.Warn("client_log", attrs...)
	case "error":
		logger.Error("client_log", attrs...)
	default:
		logger.Info("client_log", attrs...)
	}
}
