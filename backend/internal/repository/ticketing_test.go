package repository

import (
	"testing"

	"github.com/jackc/pgx/v5/pgconn"
)

// TestRequiresTransferTelegramContact verifies Telegram contact requirements only apply to ISKRY landing transfers.
func TestRequiresTransferTelegramContact(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name      string
		accessKey string
		info      map[string]interface{}
		want      bool
	}{
		{
			name:      "iskry landing requires contact",
			accessKey: iskryEventAccessKey,
			info: map[string]interface{}{
				transferLandingKeyField: transferLandingIskry,
			},
			want: true,
		},
		{
			name:      "space landing on iskry event does not require contact",
			accessKey: iskryEventAccessKey,
			info: map[string]interface{}{
				transferLandingKeyField: transferLandingSpace,
			},
			want: false,
		},
		{
			name:      "missing landing defaults to space",
			accessKey: iskryEventAccessKey,
			info:      map[string]interface{}{},
			want:      false,
		},
		{
			name:      "non iskry event never requires contact",
			accessKey: "space",
			info: map[string]interface{}{
				transferLandingKeyField: transferLandingIskry,
			},
			want: false,
		},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if got := requiresTransferTelegramContact(tc.accessKey, tc.info); got != tc.want {
				t.Fatalf("requiresTransferTelegramContact() = %v, want %v", got, tc.want)
			}
		})
	}
}

// TestIsTransferProductUniqueViolation verifies transfer product duplicate detection.
func TestIsTransferProductUniqueViolation(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name string
		err  error
		want bool
	}{
		{
			name: "legacy direction constraint",
			err: &pgconn.PgError{
				Code:           "23505",
				ConstraintName: transferProductDirectionConstraintName,
			},
			want: true,
		},
		{
			name: "landing-aware unique index",
			err: &pgconn.PgError{
				Code:           "23505",
				ConstraintName: transferProductLandingConstraintName,
			},
			want: true,
		},
		{
			name: "other unique violation",
			err: &pgconn.PgError{
				Code:           "23505",
				ConstraintName: "something_else",
			},
			want: false,
		},
		{
			name: "other sqlstate",
			err: &pgconn.PgError{
				Code:           "23514",
				ConstraintName: transferProductLandingConstraintName,
			},
			want: false,
		},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if got := isTransferProductUniqueViolation(tc.err); got != tc.want {
				t.Fatalf("isTransferProductUniqueViolation() = %v, want %v", got, tc.want)
			}
		})
	}
}
