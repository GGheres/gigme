package handlers

import (
	"reflect"
	"strings"
	"testing"

	"gigme/backend/internal/models"
)

func TestAdminTelegramIDsSorted(t *testing.T) {
	got := adminTelegramIDs(map[int64]struct{}{
		44: {},
		10: {},
		-1: {},
		0:  {},
		77: {},
	})
	want := []int64{10, 44, 77}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("adminTelegramIDs() = %v, want %v", got, want)
	}
}

func TestBuildAdminOrderNotificationText(t *testing.T) {
	order := models.Order{
		ID:            "ord-1",
		UserID:        555,
		EventID:       42,
		EventTitle:    "Techno Night",
		Status:        "pending",
		PaymentMethod: models.PaymentMethodQR,
		TotalCents:    159900,
		Currency:      "RUB",
	}

	got := buildAdminOrderNotificationText(order, 0, 777001, "@my_bot")
	parts := []string{
		"Новый заказ",
		"Заказ: ord-1",
		"Пользователь ID: 555",
		"Пользователь TG: 777001",
		"Команда ответа: /reply 777001 <текст>",
		"Ответить в боте: https://t.me/my_bot?start=reply_777001",
		"Событие: Techno Night",
		"Оплата: PAYMENT_QR",
		"Сумма: 1599.00 RUB",
		"Статус: PENDING",
	}
	for _, part := range parts {
		if !strings.Contains(got, part) {
			t.Fatalf("expected %q in %q", part, got)
		}
	}
}

func TestBuildAdminOrderNotificationTextUsesFallbackUserID(t *testing.T) {
	order := models.Order{
		ID:      "ord-2",
		EventID: 8,
	}
	got := buildAdminOrderNotificationText(order, 999, 0, "")
	if !strings.Contains(got, "Пользователь ID: 999") {
		t.Fatalf("expected fallback user id in %q", got)
	}
}

func TestIncomingTelegramMessageTextPrefersText(t *testing.T) {
	msg := &telegramMessage{
		Text:    "  hello from user  ",
		Caption: "caption text",
	}
	if got := incomingTelegramMessageText(msg); got != "hello from user" {
		t.Fatalf("incomingTelegramMessageText() = %q, want %q", got, "hello from user")
	}
}

func TestBuildAdminBotMessageNotificationText(t *testing.T) {
	msg := telegramMessage{
		MessageID: 77,
		Text:      "Нужна помощь с заказом",
		Chat:      telegramChat{ID: 123456},
		From: telegramFrom{
			ID:        123456,
			Username:  "alex_user",
			FirstName: "Alex",
			LastName:  "Doe",
		},
	}

	got := buildAdminBotMessageNotificationText(msg, "my_bot")
	parts := []string{
		"Новое сообщение в боте",
		"От: Alex Doe (@alex_user)",
		"Chat ID: 123456",
		"Ответ: /reply 123456 <текст>",
		"Открыть бота: https://t.me/my_bot?start=reply_123456",
		"Message ID: 77",
		"Текст:",
		"Нужна помощь с заказом",
	}
	for _, part := range parts {
		if !strings.Contains(got, part) {
			t.Fatalf("expected %q in %q", part, got)
		}
	}
}

func TestBuildAdminBotMessageNotificationTextEmpty(t *testing.T) {
	msg := telegramMessage{}
	if got := buildAdminBotMessageNotificationText(msg, ""); got != "" {
		t.Fatalf("expected empty text, got %q", got)
	}
}

func TestBuildAdminReplyMarkup(t *testing.T) {
	markup := buildAdminReplyMarkup("@my_bot", 123456)
	if markup == nil {
		t.Fatalf("expected markup")
	}
	if len(markup.InlineKeyboard) != 1 {
		t.Fatalf("expected one row, got %d", len(markup.InlineKeyboard))
	}
	row := markup.InlineKeyboard[0]
	if len(row) != 3 {
		t.Fatalf("expected three buttons, got %d", len(row))
	}

	openButton := row[0]
	if openButton.Text != "Ответить" {
		t.Fatalf("unexpected open button text: %q", openButton.Text)
	}
	if openButton.CallbackData != "reply:123456" {
		t.Fatalf("unexpected callback data: %q", openButton.CallbackData)
	}
	if openButton.URL != "" {
		t.Fatalf("unexpected URL for callback button: %q", openButton.URL)
	}

	templateButton := row[1]
	if templateButton.Text != "Шаблон /reply" {
		t.Fatalf("unexpected template button text: %q", templateButton.Text)
	}
	if templateButton.CallbackData != "reply_hint:123456" {
		t.Fatalf("unexpected template callback data: %q", templateButton.CallbackData)
	}
	if templateButton.CopyText != nil {
		t.Fatalf("unexpected copy_text payload: %+v", templateButton.CopyText)
	}
	if templateButton.URL != "" {
		t.Fatalf("unexpected template button URL: %q", templateButton.URL)
	}

	openChatButton := row[2]
	if openChatButton.Text != "Открыть чат" {
		t.Fatalf("unexpected open chat button text: %q", openChatButton.Text)
	}
	if openChatButton.URL != "https://t.me/my_bot?start=reply_123456" {
		t.Fatalf("unexpected open chat url: %q", openChatButton.URL)
	}
}

func TestBuildAdminReplyMarkupWithoutBotUsername(t *testing.T) {
	markup := buildAdminReplyMarkup("", 123)
	if markup == nil {
		t.Fatalf("expected markup with copy button")
	}
	if len(markup.InlineKeyboard) != 1 || len(markup.InlineKeyboard[0]) != 2 {
		t.Fatalf("expected two callback buttons row, got %+v", markup.InlineKeyboard)
	}
	button := markup.InlineKeyboard[0][0]
	if button.Text != "Ответить" {
		t.Fatalf("unexpected button text: %q", button.Text)
	}
	if button.CallbackData != "reply:123" {
		t.Fatalf("unexpected callback data: %q", button.CallbackData)
	}
	if button.URL != "" || button.WebApp != nil || button.CopyText != nil {
		t.Fatalf("unexpected extra button fields: %+v", button)
	}
}

func TestBuildAdminReplyMarkupInvalidChat(t *testing.T) {
	if markup := buildAdminReplyMarkup("my_bot", 0); markup != nil {
		t.Fatalf("expected nil markup, got %+v", markup)
	}
}
