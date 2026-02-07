package tests

import (
	"testing"
	"time"

	"gigme/backend/internal/eventparser/extract"
)

func TestParseDateTimeEnglishAndRussian(t *testing.T) {
	tests := []struct {
		name  string
		input string
		year  int
		month time.Month
		day   int
		hour  int
		min   int
	}{
		{
			name:  "english",
			input: "Join us on 12 January 2026 at 19:30 in Amsterdam",
			year:  2026,
			month: time.January,
			day:   12,
			hour:  19,
			min:   30,
		},
		{
			name:  "russian",
			input: "Концерт 7 февраля 2026 в 20:15, место: Москва",
			year:  2026,
			month: time.February,
			day:   7,
			hour:  20,
			min:   15,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			parsed, err := extract.ParseDateTime(tt.input)
			if err != nil {
				t.Fatalf("parse failed: %v", err)
			}
			if parsed == nil {
				t.Fatalf("parsed date is nil")
			}
			if parsed.Year() != tt.year || parsed.Month() != tt.month || parsed.Day() != tt.day {
				t.Fatalf("unexpected date: %v", parsed)
			}
			if parsed.Hour() != tt.hour || parsed.Minute() != tt.min {
				t.Fatalf("unexpected time: %v", parsed)
			}
		})
	}
}
