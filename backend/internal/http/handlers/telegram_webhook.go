package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
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

// telegramUpdate represents telegram update.
type telegramUpdate struct {
	Message       *telegramMessage       `json:"message"`
	CallbackQuery *telegramCallbackQuery `json:"callback_query"`
}

// telegramMessage represents telegram message.
type telegramMessage struct {
	MessageID int                 `json:"message_id"`
	Text      string              `json:"text"`
	Caption   string              `json:"caption"`
	Chat      telegramChat        `json:"chat"`
	From      telegramFrom        `json:"from"`
	Photo     []telegramPhotoSize `json:"photo"`
	Document  *telegramDocument   `json:"document"`
}

// telegramPhotoSize represents Telegram photo size metadata.
type telegramPhotoSize struct {
	FileID string `json:"file_id"`
}

// telegramDocument represents Telegram document metadata.
type telegramDocument struct {
	FileID   string `json:"file_id"`
	FileName string `json:"file_name"`
	MimeType string `json:"mime_type"`
	FileSize int64  `json:"file_size"`
}

// telegramChat represents telegram chat.
type telegramChat struct {
	ID int64 `json:"id"`
}

// telegramFrom represents telegram from.
type telegramFrom struct {
	ID        int64  `json:"id"`
	Username  string `json:"username"`
	FirstName string `json:"first_name"`
	LastName  string `json:"last_name"`
}

// telegramCallbackQuery represents telegram callback query.
type telegramCallbackQuery struct {
	ID      string           `json:"id"`
	From    telegramFrom     `json:"from"`
	Message *telegramMessage `json:"message"`
	Data    string           `json:"data"`
}

var startEventPayloadRe = regexp.MustCompile(`(?i)event_(\d+)(?:_([a-z0-9_-]+))?`)
var startEventIDRe = regexp.MustCompile(`\d+`)
var adminReplyPayloadRe = regexp.MustCompile(`(?i)(?:reply|chat)_(\d+)`)
var adminReplyCallbackDataRe = regexp.MustCompile(`(?i)^reply:(\d+)$`)
var adminReplyHintCallbackDataRe = regexp.MustCompile(`(?i)^reply_hint:(\d+)$`)

const (
	telegramStartMenuText              = "Выберите раздел SPACE APP"
	telegramManagerPromptText          = "Введите пароль менеджера одним сообщением"
	telegramManagerEnabledText         = "Режим менеджера включен. Нажмите кнопку ниже, чтобы открыть SPACE APP."
	telegramManagerAlreadyEnabledText  = "Режим менеджера уже включен. Нажмите кнопку ниже, чтобы открыть SPACE APP."
	telegramManagerInvalidPasswordText = "Неверный пароль менеджера. Отправьте /manager и попробуйте еще раз."
	telegramManagerDisabledText        = "Режим менеджера сейчас не настроен."
)

// parseStartPayload parses start payload.
func parseStartPayload(payload string) (int64, string) {
	payload = strings.TrimSpace(payload)
	if payload == "" {
		return 0, ""
	}
	lower := strings.ToLower(payload)
	if strings.HasPrefix(lower, "reply_") || strings.HasPrefix(lower, "chat_") {
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

// TelegramWebhook handles telegram webhook.
func (h *Handler) TelegramWebhook(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	var update telegramUpdate
	if err := json.NewDecoder(r.Body).Decode(&update); err != nil {
		logger.Warn("action", "action", "telegram_webhook", "status", "invalid_json")
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	if update.CallbackQuery != nil {
		h.handleTelegramCallbackQuery(logger, update.CallbackQuery)
		writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
		return
	}
	if update.Message == nil || update.Message.Chat.ID == 0 {
		writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
		return
	}

	text := incomingTelegramMessageText(update.Message)
	trimmedText := strings.TrimSpace(text)
	isAdmin := h.isAdminTelegramID(update.Message.From.ID)

	if isAdmin {
		if h.handleAdminTelegramMessage(r.Context(), logger, update.Message, trimmedText) {
			writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
			return
		}
	}

	if h.handleTelegramManagerMessage(logger, update.Message, trimmedText) {
		writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
		return
	}

	if !isAdmin {
		h.storeIncomingBotMessage(r.Context(), logger, update.Message, trimmedText)
		h.forwardIncomingBotMediaToAdmins(logger, update.Message)
		h.notifyAdminsWithMarkup(
			logger,
			buildAdminBotMessageNotificationText(*update.Message, h.cfg.TelegramUser),
			buildAdminReplyMarkup(h.cfg.TelegramUser, update.Message.Chat.ID),
		)
	}

	fields := strings.Fields(trimmedText)
	if len(fields) == 0 || !strings.HasPrefix(fields[0], "/start") {
		writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
		return
	}

	webAppURL := normalizeWebAppBaseURL(h.cfg.BaseURL)
	startPayload := strings.TrimSpace(strings.TrimPrefix(trimmedText, "/start"))
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
				markup = buildTelegramStartMenuMarkup(webAppURL, eventID, accessKey, "")
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

	openURLOverride := ""
	if h.hasTelegramManagerAccess(update.Message.From.ID) {
		openURLOverride = buildAdminPanelURL(webAppURL)
	}
	markup := buildTelegramStartMenuMarkup(webAppURL, 0, "", openURLOverride)

	if err := h.telegram.SendMessageWithMarkup(update.Message.Chat.ID, telegramStartMenuText, markup); err != nil {
		logger.Warn("action", "action", "telegram_webhook", "status", "send_failed", "error", err)

	}

	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

// forwardIncomingBotMediaToAdmins copies incoming user media messages to each admin chat.
func (h *Handler) forwardIncomingBotMediaToAdmins(logger *slog.Logger, message *telegramMessage) {
	if h == nil || h.telegram == nil || h.cfg == nil || message == nil {
		return
	}
	if !telegramMessageHasCopyableMedia(message) {
		return
	}
	adminIDs := adminTelegramIDs(h.cfg.AdminTGIDs)
	if len(adminIDs) == 0 {
		return
	}
	markup := buildAdminReplyMarkup(h.cfg.TelegramUser, message.Chat.ID)
	for _, adminID := range adminIDs {
		if err := h.telegram.CopyMessage(adminID, message.Chat.ID, int64(message.MessageID), markup); err != nil {
			if logger != nil {
				logger.Warn(
					"action", "action", "telegram_webhook_copy_media_to_admin",
					"status", "copy_failed",
					"admin_telegram_id", adminID,
					"chat_id", message.Chat.ID,
					"message_id", message.MessageID,
					"error", err,
				)
			}
		}
	}
}

// telegramMessageHasCopyableMedia reports whether message contains media worth copying to admins.
func telegramMessageHasCopyableMedia(message *telegramMessage) bool {
	if message == nil {
		return false
	}
	if len(message.Photo) > 0 {
		return true
	}
	return message.Document != nil && strings.TrimSpace(message.Document.FileID) != ""
}

// isAdminTelegramID reports whether admin telegram i d condition is met.
func (h *Handler) isAdminTelegramID(telegramID int64) bool {
	if h == nil || h.cfg == nil || telegramID <= 0 {
		return false
	}
	_, ok := h.cfg.AdminTGIDs[telegramID]
	return ok
}

// handleTelegramCallbackQuery handles telegram callback query.
func (h *Handler) handleTelegramCallbackQuery(logger *slog.Logger, query *telegramCallbackQuery) {
	if h == nil || h.telegram == nil || query == nil {
		return
	}

	_ = h.telegram.AnswerCallbackQuery(query.ID, "")

	adminTelegramID := query.From.ID
	if !h.isAdminTelegramID(adminTelegramID) {
		return
	}

	chatID, isHint, ok := parseAdminReplyCallbackData(query.Data)
	if !ok || chatID <= 0 {
		return
	}

	h.setAdminReplyTarget(adminTelegramID, chatID)

	replyChatID := adminTelegramID
	if query.Message != nil && query.Message.Chat.ID > 0 {
		replyChatID = query.Message.Chat.ID
	}

	text := fmt.Sprintf(
		"Режим ответа включен для %d\nОтправьте текст одним сообщением\nОтключить: /cancelreply",
		chatID,
	)
	if isHint {
		text = fmt.Sprintf("%s\nШаблон: /reply %d <текст>", text, chatID)
	}
	if err := h.telegram.SendMessage(replyChatID, text); err != nil {
		logger.Warn(
			"action", "action", "telegram_webhook_admin_reply_callback",
			"status", "send_failed",
			"admin_telegram_id", adminTelegramID,
			"chat_id", chatID,
			"error", err,
		)
	}

}

// handleAdminTelegramMessage handles admin telegram message.
func (h *Handler) handleAdminTelegramMessage(ctx context.Context, logger *slog.Logger, message *telegramMessage, text string) bool {
	if h == nil || h.telegram == nil || message == nil {
		return false
	}

	if chatID, replyText, ok := parseAdminReplyCommand(text); ok {
		if err := h.telegram.SendMessage(chatID, replyText); err != nil {
			logger.Warn(
				"action", "action", "telegram_webhook_admin_reply",
				"status", "send_failed",
				"admin_telegram_id", message.From.ID,
				"chat_id", chatID,
				"error", err,
			)
			_ = h.telegram.SendMessage(
				message.Chat.ID,
				fmt.Sprintf("Не удалось отправить сообщение пользователю %d", chatID),
			)
			return true
		}
		h.setAdminReplyTarget(message.From.ID, chatID)
		h.storeOutgoingBotMessage(ctx, logger, chatID, message.From.ID, replyText)
		_ = h.telegram.SendMessage(
			message.Chat.ID,
			fmt.Sprintf("Сообщение отправлено пользователю %d", chatID),
		)
		return true
	}

	lower := strings.ToLower(strings.TrimSpace(text))
	if strings.HasPrefix(lower, "/cancelreply") {
		h.clearAdminReplyTarget(message.From.ID)
		_ = h.telegram.SendMessage(message.Chat.ID, "Режим ответа выключен")
		return true
	}
	if chatID, ok := parseAdminReplyTargetCommand(text); ok {
		h.setAdminReplyTarget(message.From.ID, chatID)
		_ = h.telegram.SendMessage(
			message.Chat.ID,
			fmt.Sprintf("Режим ответа включен для %d\nОтправьте текст одним сообщением\nОтключить: /cancelreply", chatID),
		)
		return true
	}
	if strings.HasPrefix(lower, "/reply") {
		_ = h.telegram.SendMessage(message.Chat.ID, adminReplyUsageText(0, h.cfg.TelegramUser))
		return true
	}

	if strings.HasPrefix(lower, "/start") {
		startPayload := strings.TrimSpace(strings.TrimPrefix(text, "/start"))
		if chatID, ok := parseAdminReplyPayload(startPayload); ok {
			h.setAdminReplyTarget(message.From.ID, chatID)
			_ = h.telegram.SendMessage(
				message.Chat.ID,
				fmt.Sprintf("Режим ответа включен для %d\nОтправьте текст одним сообщением\n%s\nОтключить: /cancelreply", chatID, adminReplyUsageText(chatID, h.cfg.TelegramUser)),
			)
			return true
		}
		return false
	}

	if strings.HasPrefix(lower, "/help") {
		_ = h.telegram.SendMessage(message.Chat.ID, adminReplyUsageText(0, h.cfg.TelegramUser))
		return true
	}

	replyText := strings.TrimSpace(text)
	if replyText != "" {
		if chatID, ok := h.adminReplyTargetFor(message.From.ID); ok && chatID > 0 {
			if err := h.telegram.SendMessage(chatID, replyText); err != nil {
				logger.Warn(
					"action", "action", "telegram_webhook_admin_reply_session",
					"status", "send_failed",
					"admin_telegram_id", message.From.ID,
					"chat_id", chatID,
					"error", err,
				)
				_ = h.telegram.SendMessage(
					message.Chat.ID,
					fmt.Sprintf("Не удалось отправить сообщение пользователю %d", chatID),
				)
				return true
			}
			h.storeOutgoingBotMessage(ctx, logger, chatID, message.From.ID, replyText)
			_ = h.telegram.SendMessage(
				message.Chat.ID,
				fmt.Sprintf("Сообщение отправлено пользователю %d", chatID),
			)
			return true
		}
	}

	return false
}

// handleTelegramManagerMessage handles the lightweight manager activation flow for Telegram users.
func (h *Handler) handleTelegramManagerMessage(logger *slog.Logger, message *telegramMessage, text string) bool {
	if h == nil || h.telegram == nil || message == nil || message.Chat.ID <= 0 || message.From.ID <= 0 {
		return false
	}

	if password, ok := parseManagerCommandPassword(text); ok {
		return h.completeTelegramManagerPassword(logger, message.Chat.ID, message.From.ID, password)
	}

	lower := strings.ToLower(strings.TrimSpace(text))
	if strings.HasPrefix(lower, "/manager") {
		if !h.isTelegramManagerFlowEnabled() {
			if err := h.telegram.SendMessage(message.Chat.ID, telegramManagerDisabledText); err != nil {
				logger.Warn(
					"action", "action", "telegram_webhook_manager_disabled",
					"status", "send_failed",
					"chat_id", message.Chat.ID,
					"error", err,
				)
			}
			return true
		}
		if h.hasTelegramManagerAccess(message.From.ID) {
			h.sendTelegramManagerOpenMessage(
				logger,
				message.Chat.ID,
				telegramManagerAlreadyEnabledText,
			)
			return true
		}
		h.promptTelegramManagerPassword(message.From.ID)
		if err := h.telegram.SendMessage(message.Chat.ID, telegramManagerPromptText); err != nil {
			logger.Warn(
				"action", "action", "telegram_webhook_manager_prompt",
				"status", "send_failed",
				"chat_id", message.Chat.ID,
				"error", err,
			)
		}
		return true
	}

	if !h.isAwaitingTelegramManagerPassword(message.From.ID) {
		return false
	}

	h.clearTelegramManagerPrompt(message.From.ID)
	return h.completeTelegramManagerPassword(logger, message.Chat.ID, message.From.ID, text)
}

// completeTelegramManagerPassword validates the password and enables manager mode for the Telegram account.
func (h *Handler) completeTelegramManagerPassword(logger *slog.Logger, chatID int64, telegramID int64, password string) bool {
	if h == nil || h.telegram == nil || chatID <= 0 || telegramID <= 0 {
		return false
	}

	if !h.isTelegramManagerFlowEnabled() {
		if err := h.telegram.SendMessage(chatID, telegramManagerDisabledText); err != nil {
			logger.Warn(
				"action", "action", "telegram_webhook_manager_disabled",
				"status", "send_failed",
				"chat_id", chatID,
				"error", err,
			)
		}
		return true
	}

	if !h.authenticateTelegramManagerPassword(password) {
		if err := h.telegram.SendMessage(chatID, telegramManagerInvalidPasswordText); err != nil {
			logger.Warn(
				"action", "action", "telegram_webhook_manager_invalid_password",
				"status", "send_failed",
				"chat_id", chatID,
				"error", err,
			)
		}
		return true
	}

	h.grantTelegramManagerAccess(telegramID)
	h.sendTelegramManagerOpenMessage(logger, chatID, telegramManagerEnabledText)
	return true
}

// sendTelegramManagerOpenMessage sends the manager-mode confirmation with the Space App button.
func (h *Handler) sendTelegramManagerOpenMessage(logger *slog.Logger, chatID int64, text string) {
	if h == nil || h.telegram == nil || chatID <= 0 {
		return
	}

	baseURL := ""
	if h.cfg != nil {
		baseURL = h.cfg.BaseURL
	}
	markup := buildTelegramManagerOpenMarkup(baseURL)
	var err error
	if markup == nil {
		err = h.telegram.SendMessage(chatID, text)
	} else {
		err = h.telegram.SendMessageWithMarkup(chatID, text, markup)
	}
	if err != nil {
		logger.Warn(
			"action", "action", "telegram_webhook_manager_success",
			"status", "send_failed",
			"chat_id", chatID,
			"error", err,
		)
	}
}

// setAdminReplyTarget sets admin reply target.
func (h *Handler) setAdminReplyTarget(adminTelegramID int64, chatID int64) {
	if h == nil || adminTelegramID <= 0 || chatID <= 0 {
		return
	}
	h.replyTargetsMu.Lock()
	defer h.replyTargetsMu.Unlock()
	h.adminReplyTarget[adminTelegramID] = chatID
}

// clearAdminReplyTarget handles clear admin reply target.
func (h *Handler) clearAdminReplyTarget(adminTelegramID int64) {
	if h == nil || adminTelegramID <= 0 {
		return
	}
	h.replyTargetsMu.Lock()
	defer h.replyTargetsMu.Unlock()
	delete(h.adminReplyTarget, adminTelegramID)
}

// adminReplyTargetFor handles admin reply target for.
func (h *Handler) adminReplyTargetFor(adminTelegramID int64) (int64, bool) {
	if h == nil || adminTelegramID <= 0 {
		return 0, false
	}
	h.replyTargetsMu.RLock()
	defer h.replyTargetsMu.RUnlock()
	chatID, ok := h.adminReplyTarget[adminTelegramID]
	return chatID, ok
}

// parseAdminReplyCommand parses admin reply command.
func parseAdminReplyCommand(text string) (int64, string, bool) {
	fields := strings.Fields(strings.TrimSpace(text))
	if len(fields) < 3 {
		return 0, "", false
	}
	command := strings.ToLower(strings.TrimSpace(fields[0]))
	if !strings.HasPrefix(command, "/reply") {
		return 0, "", false
	}
	chatID, err := strconv.ParseInt(fields[1], 10, 64)
	if err != nil || chatID <= 0 {
		return 0, "", false
	}
	replyText := strings.TrimSpace(strings.Join(fields[2:], " "))
	if replyText == "" {
		return 0, "", false
	}
	return chatID, replyText, true
}

// parseAdminReplyTargetCommand parses admin reply target command.
func parseAdminReplyTargetCommand(text string) (int64, bool) {
	fields := strings.Fields(strings.TrimSpace(text))
	if len(fields) < 2 {
		return 0, false
	}
	command := strings.ToLower(strings.TrimSpace(fields[0]))
	if !strings.HasPrefix(command, "/reply") {
		return 0, false
	}
	chatID, err := strconv.ParseInt(fields[1], 10, 64)
	if err != nil || chatID <= 0 {
		return 0, false
	}
	return chatID, true
}

// parseAdminReplyPayload parses admin reply payload.
func parseAdminReplyPayload(payload string) (int64, bool) {
	match := adminReplyPayloadRe.FindStringSubmatch(strings.TrimSpace(payload))
	if len(match) < 2 {
		return 0, false
	}
	chatID, err := strconv.ParseInt(match[1], 10, 64)
	if err != nil || chatID <= 0 {
		return 0, false
	}
	return chatID, true
}

// parseAdminReplyCallbackData parses admin reply callback data.
func parseAdminReplyCallbackData(data string) (int64, bool, bool) {
	raw := strings.TrimSpace(data)
	match := adminReplyCallbackDataRe.FindStringSubmatch(raw)
	if len(match) >= 2 {
		chatID, err := strconv.ParseInt(match[1], 10, 64)
		if err != nil || chatID <= 0 {
			return 0, false, false
		}
		return chatID, false, true
	}

	match = adminReplyHintCallbackDataRe.FindStringSubmatch(raw)
	if len(match) >= 2 {
		chatID, err := strconv.ParseInt(match[1], 10, 64)
		if err != nil || chatID <= 0 {
			return 0, false, false
		}
		return chatID, true, true
	}

	return 0, false, false
}

// adminReplyUsageText handles admin reply usage text.
func adminReplyUsageText(chatID int64, botUsername string) string {
	lines := []string{
		"Команда ответа пользователю:",
	}
	if chatID > 0 {
		lines = append(lines, fmt.Sprintf("/reply %d <текст>", chatID))
		if link := buildTelegramBotReplyLink(botUsername, chatID); link != "" {
			lines = append(lines, fmt.Sprintf("Ссылка: %s", link))
		}
	} else {
		lines = append(lines, "/reply <chat_id> <текст>")
	}
	lines = append(lines, "Пример: /reply 123456789 Спасибо за сообщение")
	return strings.Join(lines, "\n")
}

// storeIncomingBotMessage handles store incoming bot message.
func (h *Handler) storeIncomingBotMessage(ctx context.Context, logger *slog.Logger, message *telegramMessage, text string) {
	if h == nil || h.repo == nil || message == nil || message.Chat.ID <= 0 {
		return
	}
	saveCtx, cancel := h.withTimeout(ctx)
	defer cancel()
	if err := h.repo.StoreAdminBotIncomingMessage(
		saveCtx,
		message.Chat.ID,
		int64(message.MessageID),
		message.From.ID,
		message.From.Username,
		message.From.FirstName,
		message.From.LastName,
		text,
	); err != nil {
		logger.Warn(
			"action", "action", "telegram_webhook_store_incoming",
			"status", "db_error",
			"chat_id", message.Chat.ID,
			"error", err,
		)
	}
}

// storeOutgoingBotMessage handles store outgoing bot message.
func (h *Handler) storeOutgoingBotMessage(ctx context.Context, logger *slog.Logger, chatID int64, adminTelegramID int64, text string) {
	if h == nil || h.repo == nil || chatID <= 0 {
		return
	}
	saveCtx, cancel := h.withTimeout(ctx)
	defer cancel()
	if err := h.repo.StoreAdminBotOutgoingMessage(saveCtx, chatID, adminTelegramID, text); err != nil {
		logger.Warn(
			"action", "action", "telegram_webhook_store_outgoing",
			"status", "db_error",
			"chat_id", chatID,
			"admin_telegram_id", adminTelegramID,
			"error", err,
		)
	}
}

// buildEventCardText builds event card text.
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

// resolveEventMediaURL handles resolve event media u r l.
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

// buildEventURL builds event u r l.
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

// buildEventPurchaseURL builds a direct ticket purchase WebApp URL.
func buildEventPurchaseURL(baseURL string, eventID int64, accessKey string) string {
	if baseURL == "" || eventID <= 0 {
		return ""
	}
	return buildWebAppPathURL(
		baseURL,
		path.Join("/space_app/event", strconv.FormatInt(eventID, 10), "buy"),
		map[string]string{"key": accessKey},
	)
}

// buildEventTransferURL builds a direct transfer purchase WebApp URL.
func buildEventTransferURL(baseURL string, eventID int64, accessKey string) string {
	if baseURL == "" || eventID <= 0 {
		return ""
	}
	return buildWebAppPathURL(
		baseURL,
		path.Join("/space_app/event", strconv.FormatInt(eventID, 10), "buy"),
		map[string]string{"key": accessKey, "mode": "transfer"},
	)
}

// buildGenericPurchaseURL builds a generic ticket entrypoint WebApp URL.
func buildGenericPurchaseURL(baseURL string) string {
	return buildWebAppPathURL(baseURL, "/space_app/buy", nil)
}

// buildGenericTransferURL builds a generic transfer entrypoint WebApp URL.
func buildGenericTransferURL(baseURL string) string {
	return buildWebAppPathURL(baseURL, "/space_app/transfer", nil)
}

// buildAdminPanelURL builds the manager/admin WebApp entrypoint URL.
func buildAdminPanelURL(baseURL string) string {
	return buildWebAppPathURL(baseURL, "/space_app/admin", nil)
}

// buildWebAppPathURL replaces the normalized app path while preserving host.
func buildWebAppPathURL(baseURL string, appPath string, queryValues map[string]string) string {
	base := normalizeWebAppBaseURL(baseURL)
	appPath = normalizeWebAppPath(appPath)
	if base == "" || appPath == "" {
		return ""
	}
	parsed, err := url.Parse(base)
	if err != nil || parsed.Scheme == "" || parsed.Host == "" {
		query := encodeNonEmptyQuery(queryValues)
		if query == "" {
			return appPath
		}
		return appPath + "?" + query
	}
	parsed.Path = appPath
	query := parsed.Query()
	for key, value := range queryValues {
		if strings.TrimSpace(value) == "" {
			continue
		}
		query.Set(key, strings.TrimSpace(value))
	}
	parsed.RawQuery = query.Encode()
	parsed.Fragment = ""
	return parsed.String()
}

// normalizeWebAppPath keeps bot menu links inside the app route namespace.
func normalizeWebAppPath(value string) string {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return ""
	}
	if !strings.HasPrefix(trimmed, "/") {
		trimmed = "/" + trimmed
	}
	cleaned := path.Clean(trimmed)
	if cleaned == "." || cleaned == "/" {
		return "/space_app"
	}
	if cleaned == "/space_app" || strings.HasPrefix(cleaned, "/space_app/") {
		return cleaned
	}
	return "/space_app"
}

// encodeNonEmptyQuery serializes only non-empty query values.
func encodeNonEmptyQuery(queryValues map[string]string) string {
	if len(queryValues) == 0 {
		return ""
	}
	query := url.Values{}
	for key, value := range queryValues {
		if strings.TrimSpace(key) == "" || strings.TrimSpace(value) == "" {
			continue
		}
		query.Set(strings.TrimSpace(key), strings.TrimSpace(value))
	}
	return query.Encode()
}

// buildTelegramStartMenuMarkup returns the three WebApp buttons shown on /start.
func buildTelegramStartMenuMarkup(baseURL string, eventID int64, accessKey string, openURLOverride string) *integrations.ReplyMarkup {
	if strings.TrimSpace(baseURL) == "" {
		return nil
	}

	buyURL := buildGenericPurchaseURL(baseURL)
	transferURL := buildGenericTransferURL(baseURL)
	openURL := normalizeWebAppBaseURL(baseURL)
	if strings.TrimSpace(openURLOverride) != "" {
		openURL = strings.TrimSpace(openURLOverride)
	}
	if eventID > 0 {
		if url := buildEventPurchaseURL(baseURL, eventID, accessKey); url != "" {
			buyURL = url
		}
		if url := buildEventTransferURL(baseURL, eventID, accessKey); url != "" {
			transferURL = url
		}
		if url := buildEventURL(baseURL, eventID, accessKey); url != "" {
			openURL = url
		}
	}

	rows := make([][]integrations.InlineKeyboardButton, 0, 3)
	appendWebAppButton := func(text string, link string) {
		if strings.TrimSpace(link) == "" {
			return
		}
		rows = append(rows, []integrations.InlineKeyboardButton{{
			Text:   text,
			WebApp: &integrations.WebAppInfo{URL: link},
		}})
	}
	appendWebAppButton("КУПИТЬ БИЛЕТ", buyURL)
	appendWebAppButton("ТРАНСФЕР", transferURL)
	appendWebAppButton("ОТКРЫТЬ SPACE APP", openURL)
	if len(rows) == 0 {
		return nil
	}
	return &integrations.ReplyMarkup{InlineKeyboard: rows}
}

// buildTelegramManagerOpenMarkup builds the single button that opens Space App in manager mode.
func buildTelegramManagerOpenMarkup(baseURL string) *integrations.ReplyMarkup {
	openURL := buildAdminPanelURL(baseURL)
	if strings.TrimSpace(openURL) == "" {
		return nil
	}
	return &integrations.ReplyMarkup{
		InlineKeyboard: [][]integrations.InlineKeyboardButton{
			{{
				Text:   "ОТКРЫТЬ SPACE APP",
				WebApp: &integrations.WebAppInfo{URL: openURL},
			}},
		},
	}
}

// parseManagerCommandPassword extracts an inline password from `/manager <password>`.
func parseManagerCommandPassword(text string) (string, bool) {
	fields := strings.Fields(strings.TrimSpace(text))
	if len(fields) < 2 {
		return "", false
	}
	if !strings.HasPrefix(strings.ToLower(fields[0]), "/manager") {
		return "", false
	}
	password := strings.TrimSpace(strings.Join(fields[1:], " "))
	if password == "" {
		return "", false
	}
	return password, true
}

// buildMediaPreviewURL builds media preview u r l.
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

// mergeEventIDIntoFragment merges event i d into fragment.
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

// normalizeWebAppBaseURL normalizes web app base u r l.
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
