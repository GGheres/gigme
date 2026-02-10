package handlers

import (
	"strings"
	"testing"

	"gigme/backend/internal/models"
)

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

func TestLandingContentToResponseUsesDefaults(t *testing.T) {
	content := landingContentToResponse(models.LandingContent{})
	if content.HeroEyebrow != landingDefaultHeroEyebrow {
		t.Fatalf("expected default hero eyebrow, got %q", content.HeroEyebrow)
	}
	if content.AboutTitle != landingDefaultAboutTitle {
		t.Fatalf("expected default about title, got %q", content.AboutTitle)
	}
	if content.FooterText != landingDefaultFooterText {
		t.Fatalf("expected default footer, got %q", content.FooterText)
	}
}

func TestMergeLandingContent(t *testing.T) {
	base := models.LandingContent{
		HeroTitle:  "Old title",
		FooterText: "Old footer",
	}
	newTitle := "  New title  "
	req := upsertLandingContentRequest{
		HeroTitle: &newTitle,
	}
	merged := mergeLandingContent(base, req)
	if merged.HeroTitle != "New title" {
		t.Fatalf("expected trimmed title, got %q", merged.HeroTitle)
	}
	if merged.FooterText != "Old footer" {
		t.Fatalf("expected untouched footer, got %q", merged.FooterText)
	}
}

func TestValidateLandingContentRejectsTooLongValues(t *testing.T) {
	content := models.LandingContent{
		HeroTitle: strings.Repeat("a", 141),
	}
	if err := validateLandingContent(content); err == nil {
		t.Fatalf("expected validation error for too long heroTitle")
	}
}
