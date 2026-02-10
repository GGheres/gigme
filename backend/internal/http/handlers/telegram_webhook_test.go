package handlers

import (
	"net/url"
	"testing"
)

func TestNormalizeWebAppBaseURL(t *testing.T) {
	got := normalizeWebAppBaseURL("https://spacefestival.fun")
	want := "https://spacefestival.fun/space_app"
	if got != want {
		t.Fatalf("expected %q, got %q", want, got)
	}
}

func TestNormalizeWebAppBaseURLDropsQueryAndFragment(t *testing.T) {
	got := normalizeWebAppBaseURL("https://spacefestival.fun/?foo=bar#x=1")
	want := "https://spacefestival.fun/space_app"
	if got != want {
		t.Fatalf("expected %q, got %q", want, got)
	}
}

func TestBuildEventURLUsesSpaceAppPath(t *testing.T) {
	link := buildEventURL(normalizeWebAppBaseURL("https://spacefestival.fun"), 42, "abc_123")
	parsed, err := url.Parse(link)
	if err != nil {
		t.Fatalf("parse url: %v", err)
	}
	if parsed.Path != "/space_app" {
		t.Fatalf("expected /space_app path, got %q", parsed.Path)
	}
	if parsed.Query().Get("eventKey") != "abc_123" {
		t.Fatalf("expected eventKey query, got %q", parsed.Query().Get("eventKey"))
	}
	if parsed.Fragment != "eventId=42" {
		t.Fatalf("expected fragment eventId=42, got %q", parsed.Fragment)
	}
}
