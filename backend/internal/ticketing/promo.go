package ticketing

import "time"

type PromoRule struct {
	Code         string
	DiscountType string
	Value        int64
	UsageLimit   *int
	UsedCount    int
	ActiveFrom   *time.Time
	ActiveTo     *time.Time
	EventID      *int64
	IsActive     bool
}

type PromoValidationInput struct {
	Now           time.Time
	EventID       int64
	SubtotalCents int64
}

type PromoValidationOutput struct {
	Valid         bool
	DiscountCents int64
	TotalCents    int64
	Reason        string
}

const (
	PromoReasonOK          = ""
	PromoReasonInactive    = "inactive"
	PromoReasonOutOfWindow = "out_of_window"
	PromoReasonUsageLimit  = "usage_limit_reached"
	PromoReasonEventScope  = "event_not_allowed"
	PromoReasonBadSubtotal = "subtotal_too_low"
	PromoReasonBadDiscount = "unsupported_discount_type"
)

func ValidatePromo(rule PromoRule, in PromoValidationInput) PromoValidationOutput {
	if in.SubtotalCents <= 0 {
		return PromoValidationOutput{Valid: false, Reason: PromoReasonBadSubtotal}
	}
	if !rule.IsActive {
		return PromoValidationOutput{Valid: false, Reason: PromoReasonInactive}
	}
	now := in.Now
	if now.IsZero() {
		now = time.Now().UTC()
	}
	if rule.ActiveFrom != nil && now.Before(rule.ActiveFrom.UTC()) {
		return PromoValidationOutput{Valid: false, Reason: PromoReasonOutOfWindow}
	}
	if rule.ActiveTo != nil && now.After(rule.ActiveTo.UTC()) {
		return PromoValidationOutput{Valid: false, Reason: PromoReasonOutOfWindow}
	}
	if rule.UsageLimit != nil && *rule.UsageLimit > 0 && rule.UsedCount >= *rule.UsageLimit {
		return PromoValidationOutput{Valid: false, Reason: PromoReasonUsageLimit}
	}
	if rule.EventID != nil && *rule.EventID > 0 && *rule.EventID != in.EventID {
		return PromoValidationOutput{Valid: false, Reason: PromoReasonEventScope}
	}
	discount := applyDiscount(rule.DiscountType, rule.Value, in.SubtotalCents)
	if discount < 0 {
		return PromoValidationOutput{Valid: false, Reason: PromoReasonBadDiscount}
	}
	if discount > in.SubtotalCents {
		discount = in.SubtotalCents
	}
	return PromoValidationOutput{
		Valid:         true,
		DiscountCents: discount,
		TotalCents:    in.SubtotalCents - discount,
		Reason:        PromoReasonOK,
	}
}

func applyDiscount(discountType string, value int64, subtotalCents int64) int64 {
	if value <= 0 || subtotalCents <= 0 {
		return 0
	}
	switch discountType {
	case "PERCENT":
		if value > 100 {
			value = 100
		}
		return (subtotalCents * value) / 100
	case "FIXED":
		if value > subtotalCents {
			return subtotalCents
		}
		return value
	default:
		return -1
	}
}
