package ticketdelivery

import (
	"fmt"
	"strings"

	"gigme/backend/internal/integrations"
	"gigme/backend/internal/models"
	"gigme/backend/internal/ticketing"
)

// Sender represents a Telegram sender that can deliver QR images.
type Sender interface {
	SendMessage(chatID int64, text string) error
	SendPhotoBytes(chatID int64, filename string, photo []byte, caption string, markup *integrations.ReplyMarkup) error
}

// SendTicketQR sends a ticket or transfer QR code to Telegram.
func SendTicketQR(sender Sender, userTelegramID int64, ticket models.Ticket) error {
	if sender == nil || userTelegramID <= 0 {
		return nil
	}
	payload := strings.TrimSpace(ticket.QRPayload)
	if payload == "" {
		return nil
	}
	qrBytes, err := ticketing.GenerateQRImagePNG(payload, 420)
	if err != nil {
		return err
	}
	filename := fmt.Sprintf("ticket-%s.png", ticket.ID)
	if IsTransferTicket(ticket.TicketType) {
		filename = fmt.Sprintf("transfer-%s.png", ticket.ID)
	}
	if err := sender.SendPhotoBytes(userTelegramID, filename, qrBytes, Caption(ticket), nil); err != nil {
		return sender.SendMessage(userTelegramID, fallbackText(ticket, payload))
	}
	return nil
}

// Caption builds the Telegram QR image caption.
func Caption(ticket models.Ticket) string {
	label := "Билет"
	action := "Покажите QR-код на входе."
	if IsTransferTicket(ticket.TicketType) {
		label = "Трансфер"
		action = "Покажите QR-код при посадке."
	}
	return fmt.Sprintf(
		"%s %s\nСобытие: %d\nТип: %s\nКоличество мест: %d\n%s",
		label,
		ticket.ID,
		ticket.EventID,
		DisplayName(ticket.TicketType),
		ticket.Quantity,
		action,
	)
}

// DisplayName returns a user-facing ticket type label.
func DisplayName(ticketType string) string {
	switch strings.ToUpper(strings.TrimSpace(ticketType)) {
	case models.TicketTypeSingle:
		return "Один билет"
	case models.TicketTypeGroup2:
		return "Групповой билет на 2"
	case models.TicketTypeGroup10:
		return "Групповой билет на 10"
	case models.TicketTypeTransferThere:
		return "Трансфер туда"
	case models.TicketTypeTransferBack:
		return "Трансфер обратно"
	case models.TicketTypeTransferRoundTrip:
		return "Трансфер туда и обратно"
	default:
		return strings.ToUpper(strings.TrimSpace(ticketType))
	}
}

// IsTransferTicket reports whether a QR ticket is for a transfer.
func IsTransferTicket(ticketType string) bool {
	switch strings.ToUpper(strings.TrimSpace(ticketType)) {
	case models.TicketTypeTransferThere, models.TicketTypeTransferBack, models.TicketTypeTransferRoundTrip:
		return true
	default:
		return false
	}
}

// fallbackText builds a plain text fallback when Telegram photo upload fails.
func fallbackText(ticket models.Ticket, payload string) string {
	return fmt.Sprintf("%s %s\nQR payload: %s", DisplayName(ticket.TicketType), ticket.ID, payload)
}
