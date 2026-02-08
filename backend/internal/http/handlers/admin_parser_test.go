package handlers

import (
	"testing"
	"time"
)

func TestNormalizeImportedStartsAt(t *testing.T) {
	now := time.Date(2026, time.January, 2, 10, 0, 0, 0, time.UTC)

	cases := []struct {
		name        string
		startsAt    time.Time
		want        time.Time
		wantChanged bool
	}{
		{
			name:        "zero_uses_fallback",
			startsAt:    time.Time{},
			want:        now.Add(parserImportFallbackLead),
			wantChanged: true,
		},
		{
			name:        "past_uses_fallback",
			startsAt:    now.Add(-30 * time.Minute),
			want:        now.Add(parserImportFallbackLead),
			wantChanged: true,
		},
		{
			name:        "too_close_uses_fallback",
			startsAt:    now.Add(2 * time.Minute),
			want:        now.Add(parserImportFallbackLead),
			wantChanged: true,
		},
		{
			name:        "future_kept",
			startsAt:    now.Add(30 * time.Minute),
			want:        now.Add(30 * time.Minute),
			wantChanged: false,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, changed := normalizeImportedStartsAt(tc.startsAt, now)
			if !got.Equal(tc.want) {
				t.Fatalf("expected %s, got %s", tc.want.Format(time.RFC3339), got.Format(time.RFC3339))
			}
			if changed != tc.wantChanged {
				t.Fatalf("expected changed=%v, got %v", tc.wantChanged, changed)
			}
		})
	}
}
