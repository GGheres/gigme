package repository

import (
	"testing"

	"gigme/backend/internal/models"

	"github.com/jackc/pgx/v5/pgconn"
)

// TestFilterCurrentTransferProducts verifies legacy product scopes stay out of active catalogs.
func TestFilterCurrentTransferProducts(t *testing.T) {
	t.Parallel()

	products := []models.TransferProduct{
		{
			ID: "implicit-default",
		},
		{
			ID: "explicit-default",
			Info: map[string]interface{}{
				transferProductScopeField: transferProductDefaultScope,
			},
		},
		{
			ID: "legacy",
			Info: map[string]interface{}{
				transferProductScopeField: "legacy",
			},
		},
	}

	got := filterCurrentTransferProducts(products)
	if len(got) != 2 {
		t.Fatalf("filterCurrentTransferProducts() returned %d products, want 2", len(got))
	}
	if got[0].ID != "implicit-default" || got[1].ID != "explicit-default" {
		t.Fatalf("filterCurrentTransferProducts() returned unexpected products: %#v", got)
	}
}

// TestNormalizeTransferProductInfo verifies clients cannot create a legacy product scope.
func TestNormalizeTransferProductInfo(t *testing.T) {
	t.Parallel()

	got := normalizeTransferProductInfo(map[string]interface{}{
		transferProductScopeField: "legacy",
		"time":                    "12:00",
	})
	if got[transferProductScopeField] != transferProductDefaultScope {
		t.Fatalf("scope = %v, want %q", got[transferProductScopeField], transferProductDefaultScope)
	}
	if got["time"] != "12:00" {
		t.Fatalf("time = %v, want 12:00", got["time"])
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
