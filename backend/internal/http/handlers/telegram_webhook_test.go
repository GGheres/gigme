package handlers

import (
	"net/url"
	"testing"
)

// TestNormalizeWebAppBaseURL verifies that host-only URLs get the `/space_app` path.
func TestNormalizeWebAppBaseURL(t *testing.T) {
	got := normalizeWebAppBaseURL("https://spacefestival.fun")
	want := "https://spacefestival.fun/space_app"
	if got != want {
		t.Fatalf("expected %q, got %q", want, got)
	}
}

// TestNormalizeWebAppBaseURLDropsQueryAndFragment ensures query/fragment parts are stripped.
func TestNormalizeWebAppBaseURLDropsQueryAndFragment(t *testing.T) {
	got := normalizeWebAppBaseURL("https://spacefestival.fun/?foo=bar#x=1")
	want := "https://spacefestival.fun/space_app"
	if got != want {
		t.Fatalf("expected %q, got %q", want, got)
	}
}

// TestBuildEventURLUsesSpaceAppPath validates event deeplink composition for web app path and params.
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

// TestBuildGenericPurchaseURLs verifies bot menu links for global /start.
func TestBuildGenericPurchaseURLs(t *testing.T) {
	base := normalizeWebAppBaseURL("https://spacefestival.fun")
	tests := map[string]string{
		"buy":      buildGenericPurchaseURL(base),
		"transfer": buildGenericTransferURL(base),
	}
	wantPaths := map[string]string{
		"buy":      "/space_app/buy",
		"transfer": "/space_app/transfer",
	}
	for name, link := range tests {
		parsed, err := url.Parse(link)
		if err != nil {
			t.Fatalf("%s parse url: %v", name, err)
		}
		if parsed.Path != wantPaths[name] {
			t.Fatalf("%s expected path %q, got %q", name, wantPaths[name], parsed.Path)
		}
	}
}

// TestBuildEventPurchaseURLs verifies event-specific ticket and transfer links.
func TestBuildEventPurchaseURLs(t *testing.T) {
	base := normalizeWebAppBaseURL("https://spacefestival.fun")
	ticketLink := buildEventPurchaseURL(base, 42, "abc_123")
	transferLink := buildEventTransferURL(base, 42, "abc_123")

	ticketURL, err := url.Parse(ticketLink)
	if err != nil {
		t.Fatalf("parse ticket url: %v", err)
	}
	if ticketURL.Path != "/space_app/event/42/buy" {
		t.Fatalf("expected ticket path, got %q", ticketURL.Path)
	}
	if ticketURL.Query().Get("key") != "abc_123" {
		t.Fatalf("expected ticket key, got %q", ticketURL.Query().Get("key"))
	}
	if ticketURL.Query().Get("mode") != "" {
		t.Fatalf("expected ticket mode to be empty, got %q", ticketURL.Query().Get("mode"))
	}

	transferURL, err := url.Parse(transferLink)
	if err != nil {
		t.Fatalf("parse transfer url: %v", err)
	}
	if transferURL.Path != "/space_app/event/42/buy" {
		t.Fatalf("expected transfer path, got %q", transferURL.Path)
	}
	if transferURL.Query().Get("key") != "abc_123" {
		t.Fatalf("expected transfer key, got %q", transferURL.Query().Get("key"))
	}
	if transferURL.Query().Get("mode") != "transfer" {
		t.Fatalf("expected transfer mode, got %q", transferURL.Query().Get("mode"))
	}
}

// TestBuildTelegramStartMenuMarkup verifies the three /start WebApp buttons.
func TestBuildTelegramStartMenuMarkup(t *testing.T) {
	markup := buildTelegramStartMenuMarkup("https://spacefestival.fun", 0, "")
	if markup == nil {
		t.Fatalf("expected markup")
	}
	if len(markup.InlineKeyboard) != 3 {
		t.Fatalf("expected 3 rows, got %d", len(markup.InlineKeyboard))
	}
	wantTexts := []string{"КУПИТЬ БИЛЕТ", "ТРАНСФЕР", "ОТКРЫТЬ SPACE APP"}
	for index, want := range wantTexts {
		if len(markup.InlineKeyboard[index]) != 1 {
			t.Fatalf("expected row %d to have one button", index)
		}
		button := markup.InlineKeyboard[index][0]
		if button.Text != want {
			t.Fatalf("expected button %d text %q, got %q", index, want, button.Text)
		}
		if button.WebApp == nil || button.WebApp.URL == "" {
			t.Fatalf("expected button %d to have web app url", index)
		}
	}
}

// TestParseAdminReplyCommand verifies `/reply <chat_id> <text>` command parsing.
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

// TestParseAdminReplyTargetCommand verifies parsing of the reply target command.
func TestParseAdminReplyTargetCommand(t *testing.T) {
	chatID, ok := parseAdminReplyTargetCommand("/reply 54321")
	if !ok {
		t.Fatalf("expected target command to be parsed")
	}
	if chatID != 54321 {
		t.Fatalf("expected chat id 54321, got %d", chatID)
	}
}

// TestParseAdminReplyCallbackData checks both direct reply and hint callback formats.
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

// TestParseAdminReplyPayload verifies payload decoding for reply deep links.
func TestParseAdminReplyPayload(t *testing.T) {
	chatID, ok := parseAdminReplyPayload("reply_998877")
	if !ok {
		t.Fatalf("expected payload to be parsed")
	}
	if chatID != 998877 {
		t.Fatalf("expected chat id 998877, got %d", chatID)
	}
}

// TestParseStartPayloadSkipsReplyPayload confirms reply payload is ignored by event start parser.
func TestParseStartPayloadSkipsReplyPayload(t *testing.T) {
	eventID, key := parseStartPayload("reply_123")
	if eventID != 0 || key != "" {
		t.Fatalf("expected reply payload to be skipped, got eventID=%d key=%q", eventID, key)
	}
}
