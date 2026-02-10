package main

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

func TestBuildEventURLUsesSpaceAppPathAndEventIDQuery(t *testing.T) {
	link := buildEventURL("https://spacefestival.fun", 17)
	parsed, err := url.Parse(link)
	if err != nil {
		t.Fatalf("parse url: %v", err)
	}
	if parsed.Path != "/space_app" {
		t.Fatalf("expected /space_app path, got %q", parsed.Path)
	}
	if parsed.Query().Get("eventId") != "17" {
		t.Fatalf("expected eventId query, got %q", parsed.Query().Get("eventId"))
	}
}
