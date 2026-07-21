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
	markup := buildTelegramStartMenuMarkup("https://spacefestival.fun", 0, "", "")
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

// TestBuildTelegramStartMenuMarkupUsesManagerOpenURL verifies the Open Space App button can point to admin mode.
func TestBuildTelegramStartMenuMarkupUsesManagerOpenURL(t *testing.T) {
	overrideURL := buildAdminPanelURL("https://spacefestival.fun")
	markup := buildTelegramStartMenuMarkup(
		"https://spacefestival.fun",
		0,
		"",
		overrideURL,
	)
	if markup == nil {
		t.Fatalf("expected markup")
	}

	button := markup.InlineKeyboard[2][0]
	if button.WebApp == nil {
		t.Fatalf("expected open button web app payload")
	}
	parsed, err := url.Parse(button.WebApp.URL)
	if err != nil {
		t.Fatalf("parse url: %v", err)
	}
	if parsed.Path != "/space_app/admin" {
		t.Fatalf("expected manager open path, got %q", parsed.Path)
	}
}

// TestBuildTelegramStartMenuURLMarkup verifies the universal fallback buttons.
func TestBuildTelegramStartMenuURLMarkup(t *testing.T) {
	markup := buildTelegramStartMenuURLMarkup("https://spacefestival.fun", 0, "", "")
	if markup == nil || len(markup.InlineKeyboard) != 3 {
		t.Fatalf("expected 3 inline URL rows")
	}
	for index, row := range markup.InlineKeyboard {
		if len(row) != 1 || row[0].URL == "" || row[0].WebApp != nil {
			t.Fatalf("expected row %d to contain one URL-only button", index)
		}
	}
}

// TestIsTelegramStartCommand ensures only the exact bot command is accepted.
func TestIsTelegramStartCommand(t *testing.T) {
	tests := map[string]bool{
		"/start":                  true,
		"/START payload":          true,
		"/start@spacetickets_bot": true,
		"/starter":                false,
		"hello":                   false,
	}
	for input, want := range tests {
		if got := isTelegramStartCommand(input); got != want {
			t.Fatalf("isTelegramStartCommand(%q): expected %t, got %t", input, want, got)
		}
	}
}

// TestBuildTelegramManagerOpenMarkup verifies the dedicated manager button markup.
func TestBuildTelegramManagerOpenMarkup(t *testing.T) {
	markup := buildTelegramManagerOpenMarkup("https://spacefestival.fun")
	if markup == nil {
		t.Fatalf("expected manager markup")
	}
	if len(markup.InlineKeyboard) != 1 || len(markup.InlineKeyboard[0]) != 1 {
		t.Fatalf("unexpected manager markup rows: %+v", markup.InlineKeyboard)
	}
	button := markup.InlineKeyboard[0][0]
	if button.Text != "ОТКРЫТЬ SPACE APP" {
		t.Fatalf("unexpected button text: %q", button.Text)
	}
	if button.WebApp == nil {
		t.Fatalf("expected manager web app payload")
	}
	parsed, err := url.Parse(button.WebApp.URL)
	if err != nil {
		t.Fatalf("parse manager url: %v", err)
	}
	if parsed.Path != "/space_app/admin" {
		t.Fatalf("expected /space_app/admin path, got %q", parsed.Path)
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

// TestParseManagerCommandPassword verifies `/manager <password>` inline parsing.
func TestParseManagerCommandPassword(t *testing.T) {
	password, ok := parseManagerCommandPassword("/manager secret-pass")
	if !ok {
		t.Fatalf("expected manager password to be parsed")
	}
	if password != "secret-pass" {
		t.Fatalf("unexpected parsed password: %q", password)
	}
}

// TestParseStartPayloadSkipsReplyPayload confirms reply payload is ignored by event start parser.
func TestParseStartPayloadSkipsReplyPayload(t *testing.T) {
	eventID, key := parseStartPayload("reply_123")
	if eventID != 0 || key != "" {
		t.Fatalf("expected reply payload to be skipped, got eventID=%d key=%q", eventID, key)
	}
}
