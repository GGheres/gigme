package handlers

import "testing"

func TestBuildLandingAppURL(t *testing.T) {
	url := buildLandingAppURL("https://spacefestival.fun", 42, "abc_123")
	want := "https://spacefestival.fun/space_app?eventId=42&eventKey=abc_123"
	if url != want {
		t.Fatalf("expected %q, got %q", want, url)
	}
}

func TestBuildLandingTicketURLUsesBot(t *testing.T) {
	url := buildLandingTicketURL("@my_bot", 7, "", "https://spacefestival.fun/space_app?eventId=7")
	want := "https://t.me/my_bot?startapp=e_7"
	if url != want {
		t.Fatalf("expected %q, got %q", want, url)
	}
}

func TestBuildLandingTicketURLFallsBackToApp(t *testing.T) {
	fallback := "https://spacefestival.fun/space_app?eventId=11"
	url := buildLandingTicketURL("", 11, "", fallback)
	if url != fallback {
		t.Fatalf("expected fallback %q, got %q", fallback, url)
	}
}

func TestSanitizeLandingKey(t *testing.T) {
	got := sanitizeLandingKey("abC-12_?*#")
	if got != "abC-12_" {
		t.Fatalf("expected sanitized key abC-12_, got %q", got)
	}
}
