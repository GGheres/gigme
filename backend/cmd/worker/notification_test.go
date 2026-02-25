package main

import (
	"testing"

	"gigme/backend/internal/models"
)

// TestBuildEventCardResolvesRelativePhotoFallback verifies build event card resolves relative photo fallback behavior.
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

	if len(msg.PhotoURLs) == 0 {
		t.Fatalf("expected photo urls to be present")
	}
	if msg.PhotoURLs[0] != "https://api.spacefestival.fun/api/media/events/42/0" {
		t.Fatalf("unexpected first photo url: %q", msg.PhotoURLs[0])
	}
	if !containsString(msg.PhotoURLs, "https://api.spacefestival.fun/uploads/event.jpg") {
		t.Fatalf("expected resolved payload photo fallback, got %v", msg.PhotoURLs)
	}
}

// TestBuildEventCardUsesResolvedPhotoWhenPreviewUnavailable verifies build event card uses resolved photo when preview unavailable behavior.
func TestBuildEventCardUsesResolvedPhotoWhenPreviewUnavailable(t *testing.T) {
	job := models.NotificationJob{
		Payload: map[string]interface{}{
			"title":      "Test event",
			"photoUrl":   "uploads/event.jpg",
			"apiBaseUrl": "https://api.spacefestival.fun/api",
		},
	}

	msg := buildEventCard(job, "https://spacefestival.fun", "", "Новое событие")

	if len(msg.PhotoURLs) != 1 {
		t.Fatalf("expected single photo url, got %v", msg.PhotoURLs)
	}
	if msg.PhotoURLs[0] != "https://api.spacefestival.fun/api/uploads/event.jpg" {
		t.Fatalf("unexpected photo url: %q", msg.PhotoURLs[0])
	}
}

// TestNormalizePhotoURLProtocolRelative verifies normalize photo u r l protocol relative behavior.
func TestNormalizePhotoURLProtocolRelative(t *testing.T) {
	got := normalizePhotoURL("//cdn.spacefestival.fun/e.jpg", "https://api.spacefestival.fun/api")
	want := "https://cdn.spacefestival.fun/e.jpg"
	if got != want {
		t.Fatalf("expected %q, got %q", want, got)
	}
}

// TestBuildMediaPreviewCandidatesPreferAPIPrefixForBaseURL verifies build media preview candidates prefer a p i prefix for base u r l behavior.
func TestBuildMediaPreviewCandidatesPreferAPIPrefixForBaseURL(t *testing.T) {
	got := buildMediaPreviewCandidates(17, "", "https://spacefestival.fun")
	if len(got) < 2 {
		t.Fatalf("expected at least two candidates, got %v", got)
	}
	if got[0] != "https://spacefestival.fun/api/media/events/17/0" {
		t.Fatalf("unexpected first candidate: %q", got[0])
	}
	if got[1] != "https://spacefestival.fun/media/events/17/0" {
		t.Fatalf("unexpected second candidate: %q", got[1])
	}
}

// TestTruncateRunesKeepsLimit verifies truncate runes keeps limit behavior.
func TestTruncateRunesKeepsLimit(t *testing.T) {
	got := truncateRunes("123456", 5)
	if got != "1234…" {
		t.Fatalf("unexpected truncate value: %q", got)
	}
	if len([]rune(got)) != 5 {
		t.Fatalf("expected 5 runes, got %d", len([]rune(got)))
	}
}

// containsString handles contains string.
func containsString(values []string, target string) bool {
	for _, value := range values {
		if value == target {
			return true
		}
	}
	return false
}
