package tests

import (
	"context"
	"fmt"
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

func TestTelegramParserParsesAllMessagesForLast24HoursWithImage(t *testing.T) {
	now := time.Now().UTC()
	recent := now.Add(-3 * time.Hour).Format(time.RFC3339)
	withinDay := now.Add(-12 * time.Hour).Format(time.RFC3339)
	older := now.Add(-30 * time.Hour).Format(time.RFC3339)

	html := fmt.Sprintf(`
<div class="tgme_widget_message_wrap">
  <div class="tgme_widget_message">
    <a class="tgme_widget_message_date"><time datetime="%s">old</time></a>
    <div class="tgme_widget_message_text">Old event should be skipped</div>
  </div>
</div>
<div class="tgme_widget_message_wrap">
  <div class="tgme_widget_message">
    <a class="tgme_widget_message_date"><time datetime="%s">recent</time></a>
    <a class="tgme_widget_message_photo_wrap" style="background-image:url('https://cdn.example.com/pic.jpg')"></a>
    <div class="tgme_widget_message_text">Morning Meetup
Place: River Park</div>
  </div>
</div>
<div class="tgme_widget_message_wrap">
  <div class="tgme_widget_message">
    <a class="tgme_widget_message_date"><time datetime="%s">recent2</time></a>
    <div class="tgme_widget_message_text">Evening Meetup
Место: Loft Hall</div>
  </div>
</div>`, older, withinDay, recent)

	fetcher := &fakeFetcher{responses: map[string]fakeResponse{
		"https://t.me/s/multi": {status: 200, body: []byte(html)},
	}}
	d := newTestDispatcher(fetcher)
	events, err := d.ParseEventsWithSource(context.Background(), "https://t.me/s/multi", "telegram")
	if err != nil {
		t.Fatalf("parse many failed: %v", err)
	}
	if len(events) != 2 {
		t.Fatalf("expected 2 events from last 24 hours, got %d", len(events))
	}
	if events[0].DateTime == nil || events[1].DateTime == nil {
		t.Fatalf("expected message timestamps in parsed events")
	}
	if !events[0].DateTime.After(*events[1].DateTime) {
		t.Fatalf("expected events sorted by recency: %v >= %v", events[0].DateTime, events[1].DateTime)
	}
	if len(events[1].Links) == 0 {
		t.Fatalf("expected image link merged into links, got %v", events[1].Links)
	}
	foundImage := false
	for _, link := range events[1].Links {
		if link == "https://cdn.example.com/pic.jpg" {
			foundImage = true
			break
		}
	}
	if !foundImage {
		t.Fatalf("expected telegram photo link in event links, got %v", events[1].Links)
	}
}
