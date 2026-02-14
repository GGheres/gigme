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

	got := buildAdminOrderNotificationText(order, 0)
	parts := []string{
		"Новый заказ",
		"Заказ: ord-1",
		"Пользователь ID: 555",
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
	got := buildAdminOrderNotificationText(order, 999)
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

	got := buildAdminBotMessageNotificationText(msg)
	parts := []string{
		"Новое сообщение в боте",
		"От: Alex Doe (@alex_user)",
		"Chat ID: 123456",
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
	if got := buildAdminBotMessageNotificationText(msg); got != "" {
		t.Fatalf("expected empty text, got %q", got)
	}
}
