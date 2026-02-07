package tests

import (
	"context"
	"testing"
	"time"
)

func TestTelegramParserFixture(t *testing.T) {
	html := `
<div class="tgme_widget_message_text">Просто анонс без даты</div>
<div class="tgme_widget_message_text">
  Jazz Night
  14 февраля 2026 в 19:00
  Место: Loft Hall
  Ссылка: https://tickets.example/jazz
  <a href="https://example.com/map">map</a>
</div>`

	fetcher := &fakeFetcher{responses: map[string]fakeResponse{
		"https://t.me/s/jazzclub": {status: 200, body: []byte(html)},
	}}
	d := newTestDispatcher(fetcher)
	event, err := d.ParseEvent(context.Background(), "jazzclub")
	if err != nil {
		t.Fatalf("parse failed: %v", err)
	}
	if event.Name != "Jazz Night" {
		t.Fatalf("unexpected name: %q", event.Name)
	}
	if event.DateTime == nil {
		t.Fatalf("expected parsed date")
	}
	if event.DateTime.Year() != 2026 || event.DateTime.Month() != time.February || event.DateTime.Day() != 14 {
		t.Fatalf("unexpected date: %v", event.DateTime)
	}
	if event.Location != "Loft Hall" {
		t.Fatalf("unexpected location: %q", event.Location)
	}
	if len(event.Links) < 2 {
		t.Fatalf("expected links from text + href, got %v", event.Links)
	}
}

func TestWebParserJSONLDAndFallbackFixtures(t *testing.T) {
	jsonLDHTML := `
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "Event",
  "name": "Airbnb Style Event",
  "startDate": "2026-03-11T18:30:00Z",
  "description": "Meetup with hosts",
  "location": {
    "@type": "Place",
    "name": "Canal House",
    "address": {
      "streetAddress": "Damrak 1",
      "addressLocality": "Amsterdam"
    }
  },
  "url": "https://example.com/events/airbnb"
}
</script>
<a href="/events/airbnb/tickets">Tickets</a>`

	fallbackHTML := `
<h1>Fallback Event</h1>
<time datetime="2026-04-15T20:00:00Z">15 April 2026</time>
<address>Address: Main Square 5</address>
<p>Great night with artists</p>
<a href="https://example.com/fallback">Details</a>`

	fetcher := &fakeFetcher{responses: map[string]fakeResponse{
		"https://example.com/jsonld":   {status: 200, body: []byte(jsonLDHTML)},
		"https://example.com/fallback": {status: 200, body: []byte(fallbackHTML)},
	}}
	d := newTestDispatcher(fetcher)

	jsonEvent, err := d.ParseEvent(context.Background(), "https://example.com/jsonld")
	if err != nil {
		t.Fatalf("json-ld parse failed: %v", err)
	}
	if jsonEvent.Name != "Airbnb Style Event" {
		t.Fatalf("unexpected json-ld name: %q", jsonEvent.Name)
	}
	if jsonEvent.DateTime == nil {
		t.Fatalf("expected json-ld date")
	}

	fallbackEvent, err := d.ParseEvent(context.Background(), "https://example.com/fallback")
	if err != nil {
		t.Fatalf("fallback parse failed: %v", err)
	}
	if fallbackEvent.Name != "Fallback Event" {
		t.Fatalf("unexpected fallback name: %q", fallbackEvent.Name)
	}
	if fallbackEvent.DateTime == nil {
		t.Fatalf("expected fallback date")
	}
	if fallbackEvent.Location == "" {
		t.Fatalf("expected fallback location")
	}
}
