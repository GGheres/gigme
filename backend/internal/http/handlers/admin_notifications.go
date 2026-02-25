package handlers

import (
	"fmt"
	"log/slog"
	"sort"
	"strings"

	"gigme/backend/internal/integrations"
	"gigme/backend/internal/models"
)

const adminMessageMaxRunes = 1500

// notifyAdmins handles notify admins.
func (h *Handler) notifyAdmins(logger *slog.Logger, text string) {
	h.notifyAdminsWithMarkup(logger, text, nil)
}

// notifyAdminsWithMarkup handles notify admins with markup.
func (h *Handler) notifyAdminsWithMarkup(logger *slog.Logger, text string, markup *integrations.ReplyMarkup) {
	if h == nil || h.telegram == nil || h.cfg == nil {
		return
	}
	message := strings.TrimSpace(text)
	if message == "" {
		return
	}
	adminIDs := adminTelegramIDs(h.cfg.AdminTGIDs)
	if len(adminIDs) == 0 {
		return
	}
	for _, adminID := range adminIDs {
		err := h.telegram.SendMessageWithMarkup(adminID, message, markup)
		if err != nil && markup != nil {
			// Fallback to plain text when client/API rejects advanced markup buttons.
			err = h.telegram.SendMessage(adminID, message)
		}
		if err != nil && logger != nil {
			logger.Warn("admin_notification", "status", "send_failed", "admin_telegram_id", adminID, "error", err)
		}
	}
}

// adminTelegramIDs handles admin telegram i ds.
func adminTelegramIDs(ids map[int64]struct{}) []int64 {
	result := make([]int64, 0, len(ids))
	for id := range ids {
		if id <= 0 {
			continue
		}
		result = append(result, id)
	}
	sort.Slice(result, func(i, j int) bool {
		return result[i] < result[j]
	})
	return result
}

// buildAdminOrderNotificationText builds admin order notification text.
func buildAdminOrderNotificationText(order models.Order, fallbackUserID int64, userTelegramID int64, botUsername string) string {
	lines := []string{"Новый заказ"}

	if orderID := strings.TrimSpace(order.ID); orderID != "" {
		lines = append(lines, fmt.Sprintf("Заказ: %s", orderID))
	}

	userID := order.UserID
	if userID <= 0 {
		userID = fallbackUserID
	}
	if userID > 0 {
		lines = append(lines, fmt.Sprintf("Пользователь ID: %d", userID))
	}
	if userTelegramID > 0 {
		lines = append(lines, fmt.Sprintf("Пользователь TG: %d", userTelegramID))
		lines = append(lines, fmt.Sprintf("Команда ответа: /reply %d <текст>", userTelegramID))
		if link := buildTelegramBotReplyLink(botUsername, userTelegramID); link != "" {
			lines = append(lines, fmt.Sprintf("Ответить в боте: %s", link))
		}
	}

	if title := strings.TrimSpace(order.EventTitle); title != "" {
		lines = append(lines, fmt.Sprintf("Событие: %s", title))
	} else if order.EventID > 0 {
		lines = append(lines, fmt.Sprintf("Событие ID: %d", order.EventID))
	}

	if paymentMethod := strings.TrimSpace(order.PaymentMethod); paymentMethod != "" {
		lines = append(lines, fmt.Sprintf("Оплата: %s", paymentMethod))
	}

	currency := strings.TrimSpace(order.Currency)
	if currency == "" {
		currency = "RUB"
	}
	if order.TotalCents > 0 {
		lines = append(lines, fmt.Sprintf("Сумма: %s %s", formatAmount(order.TotalCents), currency))
	}

	if status := strings.TrimSpace(order.Status); status != "" {
		lines = append(lines, fmt.Sprintf("Статус: %s", strings.ToUpper(status)))
	}

	return strings.Join(lines, "\n")
}

// buildAdminBotMessageNotificationText builds admin bot message notification text.
func buildAdminBotMessageNotificationText(message telegramMessage, botUsername string) string {
	text := incomingTelegramMessageText(&message)
	if text == "" {
		return ""
	}

	lines := []string{"Новое сообщение в боте"}
	if sender := formatTelegramSender(message); sender != "" {
		lines = append(lines, fmt.Sprintf("От: %s", sender))
	}
	if message.Chat.ID > 0 {
		lines = append(lines, fmt.Sprintf("Chat ID: %d", message.Chat.ID))
		lines = append(lines, fmt.Sprintf("Ответ: /reply %d <текст>", message.Chat.ID))
		if link := buildTelegramBotReplyLink(botUsername, message.Chat.ID); link != "" {
			lines = append(lines, fmt.Sprintf("Открыть бота: %s", link))
		}
	}
	if message.MessageID > 0 {
		lines = append(lines, fmt.Sprintf("Message ID: %d", message.MessageID))
	}
	lines = append(lines, "Текст:")
	lines = append(lines, trimMessageForAdmin(text))
	return strings.Join(lines, "\n")
}

// incomingTelegramMessageText handles incoming telegram message text.
func incomingTelegramMessageText(message *telegramMessage) string {
	if message == nil {
		return ""
	}
	if text := strings.TrimSpace(message.Text); text != "" {
		return text
	}
	return strings.TrimSpace(message.Caption)
}

// formatTelegramSender formats telegram sender.
func formatTelegramSender(message telegramMessage) string {
	firstName := strings.TrimSpace(message.From.FirstName)
	lastName := strings.TrimSpace(message.From.LastName)
	fullName := strings.TrimSpace(strings.Join([]string{firstName, lastName}, " "))
	username := strings.TrimSpace(message.From.Username)

	switch {
	case fullName != "" && username != "":
		return fmt.Sprintf("%s (@%s)", fullName, username)
	case fullName != "":
		return fullName
	case username != "":
		return "@" + username
	case message.From.ID > 0:
		return fmt.Sprintf("user %d", message.From.ID)
	case message.Chat.ID > 0:
		return fmt.Sprintf("chat %d", message.Chat.ID)
	default:
		return ""
	}
}

// trimMessageForAdmin handles trim message for admin.
func trimMessageForAdmin(text string) string {
	raw := strings.TrimSpace(text)
	if raw == "" {
		return ""
	}
	runes := []rune(raw)
	if len(runes) <= adminMessageMaxRunes {
		return raw
	}
	if adminMessageMaxRunes <= 3 {
		return string(runes[:adminMessageMaxRunes])
	}
	return string(runes[:adminMessageMaxRunes-3]) + "..."
}

// buildTelegramBotReplyLink builds telegram bot reply link.
func buildTelegramBotReplyLink(botUsername string, chatID int64) string {
	if chatID <= 0 {
		return ""
	}
	username := normalizeTelegramBotUsername(botUsername)
	if username == "" {
		return ""
	}
	return fmt.Sprintf("https://t.me/%s?start=reply_%d", username, chatID)
}

// buildAdminReplyMarkup builds admin reply markup.
func buildAdminReplyMarkup(botUsername string, chatID int64) *integrations.ReplyMarkup {
	if chatID <= 0 {
		return nil
	}

	buttons := make([]integrations.InlineKeyboardButton, 0, 2)
	buttons = append(buttons, integrations.InlineKeyboardButton{
		Text:         "Ответить",
		CallbackData: fmt.Sprintf("reply:%d", chatID),
	})
	buttons = append(buttons, integrations.InlineKeyboardButton{
		Text:         "Шаблон /reply",
		CallbackData: fmt.Sprintf("reply_hint:%d", chatID),
	})
	if link := buildTelegramBotReplyLink(botUsername, chatID); link != "" {
		buttons = append(buttons, integrations.InlineKeyboardButton{
			Text: "Открыть чат",
			URL:  link,
		})
	}

	return &integrations.ReplyMarkup{
		InlineKeyboard: [][]integrations.InlineKeyboardButton{buttons},
	}
}

// normalizeTelegramBotUsername normalizes telegram bot username.
func normalizeTelegramBotUsername(value string) string {
	username := strings.TrimSpace(value)
	username = strings.TrimPrefix(username, "@")
	return strings.TrimSpace(username)
}
