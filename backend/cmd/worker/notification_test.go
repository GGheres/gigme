package main

import (
	"testing"

	"gigme/backend/internal/models"
)

func TestBuildEventCardResolvesRelativePhotoFallback(t *testing.T) {
	eventID := int64(42)
	job := models.NotificationJob{
		EventID: &eventID,
		Payload: map[string]interface{}{
			"eventId":      eventID,
			"title":        "Test event",
			"startsAt":     "2026-02-21T12:00:00Z",
			"addressLabel": "Main hall",
			"photoUrl":     "/uploads/event.jpg",
			"apiBaseUrl":   "https://api.spacefestival.fun/api",
		},
	}

	msg := buildEventCard(job, "https://spacefestival.fun", "", "Новое событие")

	if msg.PhotoURL != "https://api.spacefestival.fun/api/media/events/42/0" {
		t.Fatalf("unexpected primary photo url: %q", msg.PhotoURL)
	}
	if msg.FallbackPhotoURL != "https://api.spacefestival.fun/uploads/event.jpg" {
		t.Fatalf("unexpected fallback photo url: %q", msg.FallbackPhotoURL)
	}
}

func TestBuildEventCardUsesResolvedPhotoWhenPreviewUnavailable(t *testing.T) {
	job := models.NotificationJob{
		Payload: map[string]interface{}{
			"title":      "Test event",
			"photoUrl":   "uploads/event.jpg",
			"apiBaseUrl": "https://api.spacefestival.fun/api",
		},
	}

	msg := buildEventCard(job, "https://spacefestival.fun", "", "Новое событие")

	if msg.PhotoURL != "https://api.spacefestival.fun/api/uploads/event.jpg" {
		t.Fatalf("unexpected photo url: %q", msg.PhotoURL)
	}
	if msg.FallbackPhotoURL != "" {
		t.Fatalf("expected no fallback photo, got %q", msg.FallbackPhotoURL)
	}
}

func TestNormalizePhotoURLProtocolRelative(t *testing.T) {
	got := normalizePhotoURL("//cdn.spacefestival.fun/e.jpg", "https://api.spacefestival.fun/api")
	want := "https://cdn.spacefestival.fun/e.jpg"
	if got != want {
		t.Fatalf("expected %q, got %q", want, got)
	}
}

func TestTruncateRunesKeepsLimit(t *testing.T) {
	got := truncateRunes("123456", 5)
	if got != "1234…" {
		t.Fatalf("unexpected truncate value: %q", got)
	}
	if len([]rune(got)) != 5 {
		t.Fatalf("expected 5 runes, got %d", len([]rune(got)))
	}
}
