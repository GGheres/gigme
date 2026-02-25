package handlers

import "testing"

// TestValidateTopupAmount verifies validate topup amount behavior.
func TestValidateTopupAmount(t *testing.T) {
	cases := []struct {
		name    string
		amount  int64
		wantErr bool
	}{
		{name: "zero", amount: 0, wantErr: true},
		{name: "negative", amount: -5, wantErr: true},
		{name: "too_large", amount: maxTopupTokens + 1, wantErr: true},
		{name: "min", amount: 1, wantErr: false},
		{name: "max", amount: maxTopupTokens, wantErr: false},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := validateTopupAmount(tc.amount)
			if tc.wantErr && err == nil {
				t.Fatalf("expected error for amount %d", tc.amount)
			}
			if !tc.wantErr && err != nil {
				t.Fatalf("unexpected error for amount %d: %v", tc.amount, err)
			}
		})
	}
}
