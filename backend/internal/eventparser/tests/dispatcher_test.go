package tests

import (
	"context"
	"errors"
	"testing"

	"gigme/backend/internal/eventparser/core"
)

func TestDispatcherDomainSelectionAndTelegramChannelShortcut(t *testing.T) {
	fetcher := &fakeFetcher{responses: map[string]fakeResponse{
		"https://t.me/s/gigmechannel": {
			status: 200,
			body: []byte(`<div class="tgme_widget_message_text">Gig Meetup
12 January 2026 19:00
Place: Amsterdam</div>`),
		},
		"https://instagram.com/p/test": {
			status: 200,
			body:   []byte(`<meta property="og:title" content="Insta Event"><meta property="og:description" content="15 Jan 2026 20:00 Location: Loft">`),
		},
		"https://vk.com/test_event": {
			status: 200,
			body:   []byte(`<title>VK Event</title><meta property="og:description" content="16 Jan 2026 18:30 Адрес: СПб">`),
		},
		"https://example.com/event": {
			status: 200,
			body:   []byte(`<h1>Web Event</h1><time datetime="2026-01-18T18:00:00Z"></time><p>Address: Center</p>`),
		},
	}}
	d := newTestDispatcher(fetcher)
	ctx := context.Background()

	telegramEvent, err := d.ParseEvent(ctx, "gigmechannel")
	if err != nil {
		t.Fatalf("telegram parse: %v", err)
	}
	if telegramEvent.Name == "" || telegramEvent.DateTime == nil {
		t.Fatalf("unexpected telegram result: %+v", telegramEvent)
	}

	telegramURLNoScheme, err := d.ParseEvent(ctx, "t.me/s/gigmechannel")
	if err != nil {
		t.Fatalf("telegram no-scheme parse: %v", err)
	}
	if telegramURLNoScheme.Name == "" {
		t.Fatalf("expected telegram event name for no-scheme URL")
	}

	instagramEvent, err := d.ParseEvent(ctx, "https://instagram.com/p/test")
	if err != nil {
		t.Fatalf("instagram parse: %v", err)
	}
	if instagramEvent.Name != "Insta Event" {
		t.Fatalf("unexpected instagram name: %q", instagramEvent.Name)
	}

	vkEvent, err := d.ParseEvent(ctx, "https://vk.com/test_event")
	if err != nil {
		t.Fatalf("vk parse: %v", err)
	}
	if vkEvent.Name == "" {
		t.Fatalf("expected vk name")
	}

	webEvent, err := d.ParseEvent(ctx, "https://example.com/event")
	if err != nil {
		t.Fatalf("web parse: %v", err)
	}
	if webEvent.Name != "Web Event" {
		t.Fatalf("unexpected web name: %q", webEvent.Name)
	}
}

func TestDispatcherUnsupportedInput(t *testing.T) {
	d := newTestDispatcher(&fakeFetcher{responses: map[string]fakeResponse{}})
	_, err := d.ParseEvent(context.Background(), "not a url with spaces")
	if err == nil {
		t.Fatalf("expected error")
	}
	var unsupported *core.UnsupportedInputError
	if !errors.As(err, &unsupported) {
		t.Fatalf("expected UnsupportedInputError, got %T", err)
	}
}
