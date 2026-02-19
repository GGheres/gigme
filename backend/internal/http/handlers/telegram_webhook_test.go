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

func TestParseAdminReplyCommand(t *testing.T) {
	chatID, replyText, ok := parseAdminReplyCommand("/reply 12345 спасибо за сообщение")
	if !ok {
		t.Fatalf("expected command to be parsed")
	}
	if chatID != 12345 {
		t.Fatalf("expected chat id 12345, got %d", chatID)
	}
	if replyText != "спасибо за сообщение" {
		t.Fatalf("unexpected reply text: %q", replyText)
	}
}

func TestParseAdminReplyTargetCommand(t *testing.T) {
	chatID, ok := parseAdminReplyTargetCommand("/reply 54321")
	if !ok {
		t.Fatalf("expected target command to be parsed")
	}
	if chatID != 54321 {
		t.Fatalf("expected chat id 54321, got %d", chatID)
	}
}

func TestParseAdminReplyCallbackData(t *testing.T) {
	chatID, isHint, ok := parseAdminReplyCallbackData("reply:111")
	if !ok || isHint {
		t.Fatalf("expected reply callback data to be parsed")
	}
	if chatID != 111 {
		t.Fatalf("expected chat id 111, got %d", chatID)
	}

	chatID, isHint, ok = parseAdminReplyCallbackData("reply_hint:222")
	if !ok || !isHint {
		t.Fatalf("expected reply_hint callback data to be parsed")
	}
	if chatID != 222 {
		t.Fatalf("expected chat id 222, got %d", chatID)
	}
}

func TestParseAdminReplyPayload(t *testing.T) {
	chatID, ok := parseAdminReplyPayload("reply_998877")
	if !ok {
		t.Fatalf("expected payload to be parsed")
	}
	if chatID != 998877 {
		t.Fatalf("expected chat id 998877, got %d", chatID)
	}
}

func TestParseStartPayloadSkipsReplyPayload(t *testing.T) {
	eventID, key := parseStartPayload("reply_123")
	if eventID != 0 || key != "" {
		t.Fatalf("expected reply payload to be skipped, got eventID=%d key=%q", eventID, key)
	}
}
