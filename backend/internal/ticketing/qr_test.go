package ticketing

import (
	"strings"
	"testing"
	"time"
)

func TestSignAndVerifyQRPayload(t *testing.T) {
	secret := "test-secret"
	payload := BuildPayload("ticket-1", 100, 200, "SINGLE", 1, time.Date(2026, 2, 11, 10, 0, 0, 0, time.UTC), "abc")
	token, err := SignQRPayload(secret, payload)
	if err != nil {
		t.Fatalf("sign payload: %v", err)
	}

	verified, err := VerifyQRPayload(secret, token)
	if err != nil {
		t.Fatalf("verify payload: %v", err)
	}
	if verified.TicketID != payload.TicketID || verified.EventID != payload.EventID || verified.UserID != payload.UserID {
		t.Fatalf("verified payload mismatch: %#v", verified)
	}
}

func TestVerifyQRPayloadRejectsTamperedSignature(t *testing.T) {
	secret := "test-secret"
	payload := BuildPayload("ticket-1", 100, 200, "GROUP2", 2, time.Now().UTC(), "nonce")
	token, err := SignQRPayload(secret, payload)
	if err != nil {
		t.Fatalf("sign payload: %v", err)
	}
	tampered := token[:len(token)-1] + "0"
	if tampered == token {
		tampered = token[:len(token)-1] + "1"
	}

	if _, err := VerifyQRPayload(secret, tampered); err == nil {
		t.Fatalf("expected tampered token to fail")
	}
}

func TestVerifyQRPayloadRejectsMalformedToken(t *testing.T) {
	if _, err := VerifyQRPayload("secret", "bad-token"); err == nil {
		t.Fatalf("expected malformed token to fail")
	}
	if _, err := VerifyQRPayload("secret", strings.Repeat("a", 40)); err == nil {
		t.Fatalf("expected malformed token to fail")
	}
}
