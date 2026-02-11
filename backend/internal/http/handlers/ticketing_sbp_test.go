package handlers

import (
	"testing"

	"gigme/backend/internal/models"
)

func TestNormalizeProviderStatus(t *testing.T) {
	t.Parallel()

	cases := []struct {
		in   string
		want string
	}{
		{in: "Accepted", want: "PAID"},
		{in: "NotStarted", want: "PENDING"},
		{in: "Received", want: "PENDING"},
		{in: "InProgress", want: "PENDING"},
		{in: "Rejected", want: "FAILED"},
		{in: "", want: "UNKNOWN"},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.in, func(t *testing.T) {
			t.Parallel()
			if got := normalizeProviderStatus(tc.in); got != tc.want {
				t.Fatalf("normalizeProviderStatus(%q) = %q, want %q", tc.in, got, tc.want)
			}
		})
	}
}

func TestApplyPaymentTextTemplate(t *testing.T) {
	t.Parallel()

	order := models.Order{
		ID:         "order-1",
		EventID:    77,
		TotalCents: 159900,
	}
	got := applyPaymentTextTemplate(
		"Pay {amount} for order {order_id} event {event_id} ({amount_cents})",
		order,
		"1599.00",
		"fallback",
	)
	want := "Pay 1599.00 for order order-1 event 77 (159900)"
	if got != want {
		t.Fatalf("applyPaymentTextTemplate() = %q, want %q", got, want)
	}
}

func TestMergePaymentSettingsDefaultsNetwork(t *testing.T) {
	t.Parallel()

	current := models.PaymentSettings{
		PhoneNumber: "1",
		USDTNetwork: "TRC20",
	}
	empty := ""
	merged := mergePaymentSettings(current, upsertPaymentSettingsRequest{
		USDTNetwork: &empty,
	})
	if merged.USDTNetwork != "TRC20" {
		t.Fatalf("USDTNetwork = %q, want TRC20", merged.USDTNetwork)
	}
}
