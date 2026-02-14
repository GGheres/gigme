package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/url"
	"path"
	"regexp"
	"strconv"
	"strings"

	"gigme/backend/internal/integrations"
	"gigme/backend/internal/models"

	"github.com/jackc/pgx/v5"
)

type telegramUpdate struct {
	Message *telegramMessage `json:"message"`
}

type telegramMessage struct {
	MessageID int          `json:"message_id"`
	Text      string       `json:"text"`
	Caption   string       `json:"caption"`
	Chat      telegramChat `json:"chat"`
	From      telegramFrom `json:"from"`
}

type telegramChat struct {
	ID int64 `json:"id"`
}

type telegramFrom struct {
	ID        int64  `json:"id"`
	Username  string `json:"username"`
	FirstName string `json:"first_name"`
	LastName  string `json:"last_name"`
}

var startEventPayloadRe = regexp.MustCompile(`(?i)event_(\d+)(?:_([a-z0-9_-]+))?`)
var startEventIDRe = regexp.MustCompile(`\d+`)

func parseStartPayload(payload string) (int64, string) {
	payload = strings.TrimSpace(payload)
	if payload == "" {
		return 0, ""
	}
	if match := startEventPayloadRe.FindStringSubmatch(payload); len(match) >= 2 {
		if parsed, err := strconv.ParseInt(match[1], 10, 64); err == nil && parsed > 0 {
			key := ""
			if len(match) > 2 {
				key = strings.TrimSpace(match[2])
			}
			return parsed, key
		}
	}
	if match := startEventIDRe.FindString(payload); match != "" {
		if parsed, err := strconv.ParseInt(match, 10, 64); err == nil && parsed > 0 {
			return parsed, ""
		}
	}
	return 0, ""
}

func (h *Handler) TelegramWebhook(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	var update telegramUpdate
	if err := json.NewDecoder(r.Body).Decode(&update); err != nil {
		logger.Warn("action", "action", "telegram_webhook", "status", "invalid_json")
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	if update.Message == nil || update.Message.Chat.ID == 0 {
		writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
		return
	}

	text := incomingTelegramMessageText(update.Message)
	fields := strings.Fields(text)
	if len(fields) == 0 || !strings.HasPrefix(fields[0], "/start") {
		h.notifyAdmins(logger, buildAdminBotMessageNotificationText(*update.Message))
		writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
		return
	}

	webAppURL := normalizeWebAppBaseURL(h.cfg.BaseURL)
	startPayload := strings.TrimSpace(strings.TrimPrefix(text, "/start"))
	eventID, accessKey := parseStartPayload(startPayload)

	if eventID > 0 {
		ctx, cancel := h.withTimeout(r.Context())
		defer cancel()
		event, err := h.repo.GetEventByID(ctx, eventID)
		if err == nil && !event.IsHidden {
			if event.IsPrivate && (accessKey == "" || accessKey != event.AccessKey) {
				event = models.Event{}
			}
		}
		if event.ID > 0 {
			text := buildEventCardText(event)
			mediaURL := resolveEventMediaURL(ctx, h, eventID, accessKey)
			var markup *integrations.ReplyMarkup
			if webAppURL != "" {
				markup = &integrations.ReplyMarkup{
					InlineKeyboard: [][]integrations.InlineKeyboardButton{{
						{
							Text:   "Открыть событие",
							WebApp: &integrations.WebAppInfo{URL: buildEventURL(webAppURL, eventID, accessKey)},
						},
					}},
				}
			}
			if mediaURL != "" {
				if err := h.telegram.SendPhotoWithMarkup(update.Message.Chat.ID, mediaURL, text, markup); err == nil {
					writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
					return
				} else {
					logger.Warn("action", "action", "telegram_webhook", "status", "send_photo_failed", "error", err)
				}
			}
			if err := h.telegram.SendMessageWithMarkup(update.Message.Chat.ID, text, markup); err != nil {
				logger.Warn("action", "action", "telegram_webhook", "status", "send_failed", "error", err)
			}
			writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
			return
		}
		if err != nil && !errors.Is(err, pgx.ErrNoRows) {
			logger.Warn("action", "action", "telegram_webhook", "status", "event_lookup_failed", "event_id", eventID, "error", err)
		}
	}

	if webAppURL == "" {
		logger.Warn("action", "action", "telegram_webhook", "status", "missing_base_url")
		writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
		return
	}

	markup := &integrations.ReplyMarkup{
		InlineKeyboard: [][]integrations.InlineKeyboardButton{{
			{
				Text:   "Открыть SPACE",
				WebApp: &integrations.WebAppInfo{URL: webAppURL},
			},
		}},
	}

	if err := h.telegram.SendMessageWithMarkup(update.Message.Chat.ID, "Нажмите кнопку, чтобы открыть приложение", markup); err != nil {
		logger.Warn("action", "action", "telegram_webhook", "status", "send_failed", "error", err)

	}

	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func buildEventCardText(event models.Event) string {
	lines := make([]string, 0, 4)
	lines = append(lines, "Событие")
	if title := strings.TrimSpace(event.Title); title != "" {
		lines = append(lines, title)
	}
	if !event.StartsAt.IsZero() {
		lines = append(lines, event.StartsAt.Format("2006-01-02 15:04"))
	}
	if address := strings.TrimSpace(event.AddressLabel); address != "" {
		lines = append(lines, address)
	}
	out := strings.Join(lines, "\n")
	if out == "" {
		return "Событие"
	}
	return out
}

func resolveEventMediaURL(ctx context.Context, h *Handler, eventID int64, accessKey string) string {
	if h == nil || h.repo == nil || eventID <= 0 {
		return ""
	}
	media, err := h.repo.ListEventMedia(ctx, eventID)
	if err != nil || len(media) == 0 {
		return ""
	}
	apiBase := strings.TrimSpace(h.cfg.APIPublicURL)
	if apiBase == "" {
		apiBase = strings.TrimSpace(h.cfg.BaseURL)
	}
	if apiBase != "" {
		if preview := buildMediaPreviewURL(apiBase, eventID, accessKey); preview != "" {
			return preview
		}
	}
	first := strings.TrimSpace(media[0])
	if strings.HasPrefix(first, "http://") || strings.HasPrefix(first, "https://") {
		return first
	}
	return ""
}

func buildEventURL(baseURL string, eventID int64, accessKey string) string {
	if baseURL == "" || eventID <= 0 {
		return ""
	}
	parsed, err := url.Parse(baseURL)
	if err != nil || parsed.Scheme == "" {
		separator := "?"
		if strings.Contains(baseURL, "?") {
			separator = "&"
		}
		link := baseURL + separator + "eventId=" + strconv.FormatInt(eventID, 10)
		if accessKey != "" {
			link += "&eventKey=" + url.QueryEscape(accessKey)
		}
		return link
	}
	query := url.Values{}
	if accessKey != "" {
		query.Set("eventKey", accessKey)
	}
	parsed.RawQuery = query.Encode()
	parsed.Fragment = mergeEventIDIntoFragment(parsed.Fragment, eventID)
	return parsed.String()
}

func buildMediaPreviewURL(baseURL string, eventID int64, accessKey string) string {
	if baseURL == "" || eventID <= 0 {
		return ""
	}
	parsed, err := url.Parse(baseURL)
	if err != nil || parsed.Scheme == "" || parsed.Host == "" {
		return ""
	}
	query := parsed.Query()
	query.Set("eventId", strconv.FormatInt(eventID, 10))
	if accessKey != "" {
		query.Set("eventKey", accessKey)
	}
	parsed.RawQuery = query.Encode()
	parsed.Fragment = ""
	basePath := strings.TrimSpace(parsed.Path)
	parsed.Path = path.Join("/", basePath, "media", "events", strconv.FormatInt(eventID, 10), "0")
	return parsed.String()
}

func mergeEventIDIntoFragment(fragment string, eventID int64) string {
	if eventID <= 0 {
		return fragment
	}
	if fragment == "" {
		return "eventId=" + strconv.FormatInt(eventID, 10)
	}
	if strings.Contains(fragment, "eventId=") {
		return fragment
	}
	if strings.Contains(fragment, "=") {
		parsed, err := url.ParseQuery(fragment)
		if err == nil {
			parsed.Set("eventId", strconv.FormatInt(eventID, 10))
			return parsed.Encode()
		}
		return fragment + "&eventId=" + strconv.FormatInt(eventID, 10)
	}
	return fragment
}

func normalizeWebAppBaseURL(raw string) string {
	base := strings.TrimSpace(raw)
	if base == "" {
		return ""
	}

	parsed, err := url.Parse(base)
	if err != nil {
		return base
	}

	// Telegram WebApp should open the app entrypoint directly to keep initData.
	if parsed.Scheme == "" || parsed.Host == "" {
		trimmedPath := strings.TrimSpace(parsed.Path)
		if strings.HasPrefix(trimmedPath, "/space_app") {
			return trimmedPath
		}
		if strings.HasPrefix(trimmedPath, "/") {
			return "/space_app"
		}
		return base
	}

	parsed.Path = "/space_app"
	parsed.RawQuery = ""
	parsed.Fragment = ""
	return parsed.String()
}
