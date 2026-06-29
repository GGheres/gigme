package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"
)

const (
	defaultTelegramAPIBaseURL = "https://api.telegram.org"
	defaultForwardURL         = "http://api:8080/telegram/webhook"
	telegramLongPollSeconds   = 50
)

// telegramResponse represents a Bot API response containing raw updates.
type telegramResponse struct {
	OK          bool              `json:"ok"`
	Result      []json.RawMessage `json:"result"`
	Description string            `json:"description"`
}

// telegramUpdateHeader contains the update identifier needed for offset tracking.
type telegramUpdateHeader struct {
	UpdateID int64 `json:"update_id"`
}

// poller owns the outbound Telegram long-poll connection and forwards updates
// to the existing internal webhook handler.
type poller struct {
	botToken  string
	apiBase   string
	forwardTo string
	client    *http.Client
	logger    *slog.Logger
}

// main starts the Telegram polling bridge and handles graceful shutdown.
func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil)).With("service", "telegram-poller")
	botToken := strings.TrimSpace(os.Getenv("TELEGRAM_BOT_TOKEN"))
	if botToken == "" {
		logger.Error("missing_telegram_bot_token")
		os.Exit(1)
	}
	forwardTo := strings.TrimSpace(os.Getenv("TELEGRAM_FORWARD_URL"))
	if forwardTo == "" {
		forwardTo = defaultForwardURL
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	bridge := &poller{
		botToken:  botToken,
		apiBase:   defaultTelegramAPIBaseURL,
		forwardTo: forwardTo,
		client:    &http.Client{Timeout: 60 * time.Second},
		logger:    logger,
	}
	if err := bridge.disableWebhook(ctx); err != nil {
		logger.Error("disable_webhook_failed", "error", err)
		os.Exit(1)
	}
	logger.Info("telegram_polling_started", "forward_url", forwardTo)
	bridge.run(ctx)
}

// run continuously polls Telegram and retries transient failures with a bounded delay.
func (p *poller) run(ctx context.Context) {
	var offset int64
	for ctx.Err() == nil {
		nextOffset, err := p.pollOnce(ctx, offset)
		if err == nil {
			offset = nextOffset
			continue
		}
		p.logger.Warn("telegram_poll_failed", "offset", offset, "error", err)
		select {
		case <-ctx.Done():
			return
		case <-time.After(3 * time.Second):
		}
	}
}

// disableWebhook switches Telegram to getUpdates mode without discarding queued updates.
func (p *poller) disableWebhook(ctx context.Context) error {
	endpoint := p.methodURL("deleteWebhook")
	values := url.Values{"drop_pending_updates": {"false"}}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, strings.NewReader(values.Encode()))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := p.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < http.StatusOK || resp.StatusCode >= http.StatusMultipleChoices {
		return fmt.Errorf("deleteWebhook returned status %d", resp.StatusCode)
	}
	var result struct {
		OK          bool   `json:"ok"`
		Description string `json:"description"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return err
	}
	if !result.OK {
		return fmt.Errorf("deleteWebhook failed: %s", result.Description)
	}
	return nil
}

// pollOnce fetches one update batch, forwards it in order, and returns the next offset.
func (p *poller) pollOnce(ctx context.Context, offset int64) (int64, error) {
	endpoint, err := url.Parse(p.methodURL("getUpdates"))
	if err != nil {
		return offset, err
	}
	query := endpoint.Query()
	query.Set("offset", strconv.FormatInt(offset, 10))
	query.Set("timeout", strconv.Itoa(telegramLongPollSeconds))
	query.Set("allowed_updates", `["message","callback_query"]`)
	endpoint.RawQuery = query.Encode()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint.String(), nil)
	if err != nil {
		return offset, err
	}
	resp, err := p.client.Do(req)
	if err != nil {
		return offset, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return offset, fmt.Errorf("getUpdates returned status %d", resp.StatusCode)
	}

	var envelope telegramResponse
	if err := json.NewDecoder(resp.Body).Decode(&envelope); err != nil {
		return offset, err
	}
	if !envelope.OK {
		return offset, fmt.Errorf("getUpdates failed: %s", envelope.Description)
	}

	nextOffset := offset
	for _, rawUpdate := range envelope.Result {
		var header telegramUpdateHeader
		if err := json.Unmarshal(rawUpdate, &header); err != nil || header.UpdateID <= 0 {
			return offset, errors.New("Telegram returned an update without a valid update_id")
		}
		if err := p.forward(ctx, rawUpdate); err != nil {
			return offset, err
		}
		nextOffset = header.UpdateID + 1
		if p.logger != nil {
			p.logger.Info("telegram_update_forwarded", "update_id", header.UpdateID)
		}
	}
	return nextOffset, nil
}

// forward posts a raw Telegram update to the internal HTTP handler.
func (p *poller) forward(ctx context.Context, update json.RawMessage) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, p.forwardTo, bytes.NewReader(update))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := p.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < http.StatusOK || resp.StatusCode >= http.StatusMultipleChoices {
		return fmt.Errorf("internal webhook returned status %d", resp.StatusCode)
	}
	return nil
}

// methodURL constructs a Telegram Bot API method URL without logging the token.
func (p *poller) methodURL(method string) string {
	return strings.TrimRight(p.apiBase, "/") + "/bot" + p.botToken + "/" + method
}
