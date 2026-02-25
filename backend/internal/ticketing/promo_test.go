package ticketing

import (
	"testing"
	"time"
)

// TestValidatePromoPercent verifies validate promo percent behavior.
func TestValidatePromoPercent(t *testing.T) {
	now := time.Date(2026, 2, 11, 12, 0, 0, 0, time.UTC)
	limit := 10
	eventID := int64(42)
	result := ValidatePromo(PromoRule{
		Code:         "SUMMER20",
		DiscountType: "PERCENT",
		Value:        20,
		UsageLimit:   &limit,
		UsedCount:    2,
		EventID:      &eventID,
		IsActive:     true,
	}, PromoValidationInput{
		Now:           now,
		EventID:       eventID,
		SubtotalCents: 10000,
	})

	if !result.Valid {
		t.Fatalf("expected promo to be valid, got reason=%s", result.Reason)
	}
	if result.DiscountCents != 2000 {
		t.Fatalf("expected discount 2000, got %d", result.DiscountCents)
	}
	if result.TotalCents != 8000 {
		t.Fatalf("expected total 8000, got %d", result.TotalCents)
	}
}

// TestValidatePromoOutOfWindow verifies validate promo out of window behavior.
func TestValidatePromoOutOfWindow(t *testing.T) {
	now := time.Date(2026, 2, 11, 12, 0, 0, 0, time.UTC)
	activeFrom := now.Add(24 * time.Hour)
	result := ValidatePromo(PromoRule{
		DiscountType: "FIXED",
		Value:        500,
		ActiveFrom:   &activeFrom,
		IsActive:     true,
	}, PromoValidationInput{
		Now:           now,
		EventID:       1,
		SubtotalCents: 3000,
	})
	if result.Valid {
		t.Fatalf("expected promo to be invalid")
	}
	if result.Reason != PromoReasonOutOfWindow {
		t.Fatalf("expected reason=%s, got %s", PromoReasonOutOfWindow, result.Reason)
	}
}

// TestValidatePromoUsageLimit verifies validate promo usage limit behavior.
func TestValidatePromoUsageLimit(t *testing.T) {
	limit := 1
	result := ValidatePromo(PromoRule{
		DiscountType: "FIXED",
		Value:        200,
		UsageLimit:   &limit,
		UsedCount:    1,
		IsActive:     true,
	}, PromoValidationInput{
		Now:           time.Now().UTC(),
		EventID:       1,
		SubtotalCents: 1000,
	})
	if result.Valid {
		t.Fatalf("expected promo to be invalid")
	}
	if result.Reason != PromoReasonUsageLimit {
		t.Fatalf("expected reason=%s, got %s", PromoReasonUsageLimit, result.Reason)
	}
}
