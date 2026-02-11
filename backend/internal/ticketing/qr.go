package ticketing

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	qrcode "github.com/skip2/go-qrcode"
)

var (
	ErrInvalidQRPayload = errors.New("invalid qr payload")
	ErrInvalidQRSign    = errors.New("invalid qr signature")
)

type QRPayload struct {
	TicketID   string `json:"ticketId"`
	EventID    int64  `json:"eventId"`
	UserID     int64  `json:"userId"`
	TicketType string `json:"ticketType"`
	Quantity   int    `json:"quantity"`
	Nonce      string `json:"nonce"`
	IssuedAt   int64  `json:"issuedAt"`
}

func SignQRPayload(secret string, payload QRPayload) (string, error) {
	if strings.TrimSpace(secret) == "" {
		return "", fmt.Errorf("secret is required")
	}
	encoded, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}
	base := base64.RawURLEncoding.EncodeToString(encoded)
	sig := signRaw(secret, encoded)
	return base + "." + sig, nil
}

func VerifyQRPayload(secret string, token string) (QRPayload, error) {
	var payload QRPayload
	parts := strings.Split(token, ".")
	if len(parts) != 2 || strings.TrimSpace(parts[0]) == "" || strings.TrimSpace(parts[1]) == "" {
		return payload, ErrInvalidQRPayload
	}
	raw, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return payload, ErrInvalidQRPayload
	}
	expectedSig := signRaw(secret, raw)
	if subtle.ConstantTimeCompare([]byte(expectedSig), []byte(strings.ToLower(parts[1]))) != 1 {
		return payload, ErrInvalidQRSign
	}
	if err := json.Unmarshal(raw, &payload); err != nil {
		return payload, ErrInvalidQRPayload
	}
	if payload.TicketID == "" || payload.EventID <= 0 || payload.UserID <= 0 || payload.Quantity <= 0 || payload.IssuedAt <= 0 {
		return payload, ErrInvalidQRPayload
	}
	return payload, nil
}

func HashPayloadToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

func NewNonce(size int) (string, error) {
	if size <= 0 {
		size = 16
	}
	buf := make([]byte, size)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(buf), nil
}

func GenerateQRImagePNG(payload string, size int) ([]byte, error) {
	if size <= 0 {
		size = 256
	}
	return qrcode.Encode(payload, qrcode.Medium, size)
}

func signRaw(secret string, raw []byte) string {
	mac := hmac.New(sha256.New, []byte(secret))
	_, _ = mac.Write(raw)
	return hex.EncodeToString(mac.Sum(nil))
}

func BuildPayload(ticketID string, eventID int64, userID int64, ticketType string, quantity int, issuedAt time.Time, nonce string) QRPayload {
	return QRPayload{
		TicketID:   ticketID,
		EventID:    eventID,
		UserID:     userID,
		TicketType: ticketType,
		Quantity:   quantity,
		Nonce:      nonce,
		IssuedAt:   issuedAt.UTC().Unix(),
	}
}
