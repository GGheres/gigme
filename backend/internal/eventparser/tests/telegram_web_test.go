package tests

import (
	"context"
	"fmt"
	"strings"
	"testing"
	"time"
)

// TestTelegramParserFixture verifies telegram parser fixture behavior.
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

// TestWebParserJSONLDAndFallbackFixtures verifies web parser j s o n l d and fallback fixtures behavior.
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

// TestTelegramParserParsesAllMessagesForLast24HoursWithImage verifies telegram parser parses all messages for last24 hours with image behavior.
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

// TestTelegramParserReturnsPartialResultsWhenNextPageFails verifies telegram parser returns partial results when next page fails behavior.
func TestTelegramParserReturnsPartialResultsWhenNextPageFails(t *testing.T) {
	recent := time.Now().UTC().Add(-2 * time.Hour).Format(time.RFC3339)
	firstPage := fmt.Sprintf(`
<div class="tgme_widget_message_wrap">
  <div class="tgme_widget_message" data-post="sample/10">
    <a class="tgme_widget_message_date"><time datetime="%s">recent</time></a>
    <div class="tgme_widget_message_text">Single Event
Place: Main Hall</div>
  </div>
</div>`, recent)

	fetcher := &fakeFetcher{responses: map[string]fakeResponse{
		"https://t.me/s/sample":           {status: 200, body: []byte(firstPage)},
		"https://t.me/s/sample?before=10": {status: 500, body: []byte("upstream failed")},
	}}
	d := newTestDispatcher(fetcher)
	events, err := d.ParseEventsWithSource(context.Background(), "https://t.me/s/sample", "telegram")
	if err != nil {
		t.Fatalf("expected partial success, got error: %v", err)
	}
	if len(events) != 1 {
		t.Fatalf("expected one event from first page, got %d", len(events))
	}
	if events[0].Name == "" {
		t.Fatalf("expected parsed event name")
	}
}

// TestTelegramParserFallsBackWhenNoMessagesInLast24Hours verifies telegram parser falls back when no messages in last24 hours behavior.
func TestTelegramParserFallsBackWhenNoMessagesInLast24Hours(t *testing.T) {
	old := time.Now().UTC().Add(-48 * time.Hour).Format(time.RFC3339)
	html := fmt.Sprintf(`
<div class="tgme_widget_message_wrap">
  <div class="tgme_widget_message" data-post="fallback/20">
    <a class="tgme_widget_message_date"><time datetime="%s">old</time></a>
    <div class="tgme_widget_message_text">Большой ивент
20 February 2026 21:00
Место: Club Nova</div>
  </div>
</div>`, old)

	fetcher := &fakeFetcher{responses: map[string]fakeResponse{
		"https://t.me/s/fallback": {status: 200, body: []byte(html)},
	}}
	d := newTestDispatcher(fetcher)
	events, err := d.ParseEventsWithSource(context.Background(), "https://t.me/fallback", "telegram")
	if err != nil {
		t.Fatalf("expected fallback success, got error: %v", err)
	}
	if len(events) != 1 {
		t.Fatalf("expected one fallback event, got %d", len(events))
	}
	if events[0].Name == "" {
		t.Fatalf("expected event name in fallback mode")
	}
	if events[0].DateTime == nil {
		t.Fatalf("expected parsed date in fallback mode")
	}
}

// TestTelegramParserSinglePostURLParsesOnlyTargetMessage verifies telegram parser single post u r l parses only target message behavior.
func TestTelegramParserSinglePostURLParsesOnlyTargetMessage(t *testing.T) {
	old := time.Now().UTC().Add(-72 * time.Hour).Format(time.RFC3339)
	html := fmt.Sprintf(`
<div class="tgme_widget_message_wrap">
  <div class="tgme_widget_message" data-post="sample/41">
    <a class="tgme_widget_message_date"><time datetime="%s">old</time></a>
    <div class="tgme_widget_message_text">Другой пост</div>
  </div>
</div>
<div class="tgme_widget_message_wrap">
  <div class="tgme_widget_message" data-post="sample/42">
    <a class="tgme_widget_message_date"><time datetime="%s">old2</time></a>
    <a class="tgme_widget_message_photo_wrap" href="https://t.me/sample/43?single"></a>
    <div class="tgme_widget_message_text"><b>Суббота, 7 февраля</b><br/>Ритмы: HARD LINE x TMF<br/><br/>Место: Club X<br/><a href="https://tickets.example/x">tickets</a></div>
  </div>
</div>`, old, old)

	fetcher := &fakeFetcher{responses: map[string]fakeResponse{
		"https://t.me/s/sample/42": {status: 200, body: []byte(html)},
	}}
	d := newTestDispatcher(fetcher)
	events, err := d.ParseEventsWithSource(context.Background(), "https://t.me/sample/42", "telegram")
	if err != nil {
		t.Fatalf("single post parse failed: %v", err)
	}
	if len(events) != 1 {
		t.Fatalf("expected exactly one parsed event, got %d", len(events))
	}
	event := events[0]
	if strings.Contains(event.Description, "Другой пост") {
		t.Fatalf("unexpected text from another post in description: %q", event.Description)
	}
	if !strings.Contains(event.Description, "\n") {
		t.Fatalf("expected multiline description with line breaks, got %q", event.Description)
	}
	if event.Location != "Club X" {
		t.Fatalf("unexpected location: %q", event.Location)
	}
	foundTicket := false
	for _, link := range event.Links {
		if link == "https://tickets.example/x" {
			foundTicket = true
		}
		if strings.Contains(link, "/sample/43") {
			t.Fatalf("expected filtered out adjacent telegram post links, got %v", event.Links)
		}
	}
	if !foundTicket {
		t.Fatalf("expected ticket link in parsed links, got %v", event.Links)
	}
}

// TestTelegramParserMediaOrderFollowsMessageAndSkipsAvatar verifies telegram parser media order follows message and skips avatar behavior.
func TestTelegramParserMediaOrderFollowsMessageAndSkipsAvatar(t *testing.T) {
	now := time.Now().UTC().Add(-1 * time.Hour).Format(time.RFC3339)
	html := fmt.Sprintf(`
<div class="tgme_widget_message_wrap">
  <div class="tgme_widget_message" data-post="order/55">
    <div class="tgme_widget_message_user_photo"><img src="https://cdn.example.com/avatar.jpg"/></div>
    <a class="tgme_widget_message_date"><time datetime="%s">recent</time></a>
    <a class="tgme_widget_message_photo_wrap" style="background-image:url('https://cdn.example.com/1.jpg')"></a>
    <a class="tgme_widget_message_photo_wrap" style="background-image:url('https://cdn.example.com/2.jpg')"></a>
    <div class="tgme_widget_message_text">Line one<br/>Line two</div>
  </div>
</div>`, now)

	fetcher := &fakeFetcher{responses: map[string]fakeResponse{
		"https://t.me/s/order": {status: 200, body: []byte(html)},
	}}
	d := newTestDispatcher(fetcher)
	events, err := d.ParseEventsWithSource(context.Background(), "https://t.me/order", "telegram")
	if err != nil {
		t.Fatalf("parse failed: %v", err)
	}
	if len(events) != 1 {
		t.Fatalf("expected 1 event, got %d", len(events))
	}
	images := make([]string, 0)
	for _, link := range events[0].Links {
		if strings.HasSuffix(strings.ToLower(link), ".jpg") {
			images = append(images, link)
		}
	}
	if len(images) < 2 {
		t.Fatalf("expected ordered photo links, got %v", events[0].Links)
	}
	if images[0] != "https://cdn.example.com/1.jpg" || images[1] != "https://cdn.example.com/2.jpg" {
		t.Fatalf("expected media order [1,2], got %v", images)
	}
	for _, image := range images {
		if image == "https://cdn.example.com/avatar.jpg" {
			t.Fatalf("avatar must not be treated as event media: %v", images)
		}
	}
}
