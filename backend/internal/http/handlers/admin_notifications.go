package handlers

import (
	"fmt"
	"log/slog"
	"sort"
	"strings"

	"gigme/backend/internal/models"
)

const adminMessageMaxRunes = 1500

func (h *Handler) notifyAdmins(logger *slog.Logger, text string) {
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
		if err := h.telegram.SendMessage(adminID, message); err != nil && logger != nil {
			logger.Warn("admin_notification", "status", "send_failed", "admin_telegram_id", adminID, "error", err)
		}
	}
}

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

func buildAdminOrderNotificationText(order models.Order, fallbackUserID int64) string {
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

func buildAdminBotMessageNotificationText(message telegramMessage) string {
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
	}
	if message.MessageID > 0 {
		lines = append(lines, fmt.Sprintf("Message ID: %d", message.MessageID))
	}
	lines = append(lines, "Текст:")
	lines = append(lines, trimMessageForAdmin(text))
	return strings.Join(lines, "\n")
}

func incomingTelegramMessageText(message *telegramMessage) string {
	if message == nil {
		return ""
	}
	if text := strings.TrimSpace(message.Text); text != "" {
		return text
	}
	return strings.TrimSpace(message.Caption)
}

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
