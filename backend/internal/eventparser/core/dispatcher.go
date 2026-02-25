package core

import (
	"context"
	"errors"
	"fmt"
	"net/url"
	"sort"
	"strings"

	"golang.org/x/net/publicsuffix"
)

// Dispatcher represents dispatcher.
type Dispatcher struct {
	parsers map[SourceType]Parser
}

// NewDispatcher creates dispatcher.
func NewDispatcher(parsers map[SourceType]Parser) *Dispatcher {
	cloned := make(map[SourceType]Parser, len(parsers))
	for k, v := range parsers {
		cloned[k] = v
	}
	return &Dispatcher{parsers: cloned}
}

// ParseEvent parses event.
func (d *Dispatcher) ParseEvent(ctx context.Context, input string) (*EventData, error) {
	return d.ParseEventWithSource(ctx, input, SourceAuto)
}

// ParseEventWithSource parses event with source.
func (d *Dispatcher) ParseEventWithSource(ctx context.Context, input string, explicit SourceType) (*EventData, error) {
	events, err := d.ParseEventsWithSource(ctx, input, explicit)
	if err != nil {
		return nil, err
	}
	if len(events) == 0 {
		return nil, fmt.Errorf("no events parsed")
	}
	return events[0], nil
}

// ParseEventsWithSource parses events with source.
func (d *Dispatcher) ParseEventsWithSource(ctx context.Context, input string, explicit SourceType) ([]*EventData, error) {
	if d == nil {
		return nil, errors.New("dispatcher is nil")
	}
	raw := strings.TrimSpace(input)
	if raw == "" {
		return nil, &UnsupportedInputError{Input: input, Hint: "provide URL or Telegram channel"}
	}

	normalizedInput := raw
	source := explicit
	if source == "" {
		source = SourceAuto
	}
	if !source.Valid() {
		return nil, fmt.Errorf("invalid source type: %s", source)
	}

	if source == SourceAuto {
		parsedURL, ok := parseHTTPURL(raw)
		if ok {
			source = SourceFromURL(parsedURL)
			normalizedInput = parsedURL.String()
		} else {
			channel, ok := normalizeTelegramChannel(raw)
			if !ok {
				return nil, &UnsupportedInputError{Input: raw, Hint: "expected URL or Telegram channel name"}
			}
			source = SourceTelegram
			normalizedInput = "https://t.me/s/" + channel
		}
	} else {
		if parsedURL, ok := parseHTTPURL(raw); ok {
			normalizedInput = parsedURL.String()
		} else if source == SourceTelegram {
			channel, ok := normalizeTelegramChannel(raw)
			if !ok {
				return nil, &UnsupportedInputError{Input: raw, Hint: "expected Telegram URL or channel name"}
			}
			normalizedInput = "https://t.me/s/" + channel
		} else {
			return nil, &UnsupportedInputError{Input: raw, Hint: "explicit non-telegram source requires URL input"}
		}
	}

	parser := d.parsers[source]
	if parser == nil {
		return nil, fmt.Errorf("parser not configured for source: %s", source)
	}
	if batchParser, ok := parser.(BatchParser); ok {
		items, err := batchParser.ParseMany(ctx, normalizedInput)
		if err != nil {
			return nil, err
		}
		return normalizeEvents(items), nil
	}
	item, err := parser.Parse(ctx, normalizedInput)
	if err != nil {
		return nil, err
	}
	return normalizeEvents([]*EventData{item}), nil
}

// SourceFromURL handles source from u r l.
func SourceFromURL(u *url.URL) SourceType {
	if u == nil {
		return SourceWeb
	}
	host := strings.ToLower(strings.TrimSpace(u.Hostname()))
	if host == "" {
		return SourceWeb
	}
	if host == "t.me" || strings.HasSuffix(host, ".t.me") {
		return SourceTelegram
	}
	eTLD1, err := publicsuffix.EffectiveTLDPlusOne(host)
	if err != nil {
		eTLD1 = host
	}
	switch eTLD1 {
	case "instagram.com":
		return SourceInstagram
	case "vk.com":
		return SourceVK
	case "t.me":
		return SourceTelegram
	default:
		return SourceWeb
	}
}

// parseHTTPURL parses h t t p u r l.
func parseHTTPURL(raw string) (*url.URL, bool) {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return nil, false
	}
	candidates := []string{trimmed}
	lower := strings.ToLower(trimmed)
	if !strings.Contains(lower, "://") {
		if strings.HasPrefix(lower, "t.me/") ||
			strings.HasPrefix(lower, "www.t.me/") ||
			strings.HasPrefix(lower, "telegram.me/") ||
			strings.HasPrefix(lower, "www.telegram.me/") {
			candidates = append([]string{"https://" + trimmed}, candidates...)
		}
	}
	for _, candidate := range candidates {
		u, err := url.Parse(candidate)
		if err != nil || u == nil {
			continue
		}
		if u.Scheme == "" || u.Host == "" {
			continue
		}
		scheme := strings.ToLower(u.Scheme)
		if scheme != "http" && scheme != "https" {
			continue
		}
		return u, true
	}
	return nil, false
}

// normalizeTelegramChannel normalizes telegram channel.
func normalizeTelegramChannel(input string) (string, bool) {
	raw := strings.TrimSpace(strings.TrimPrefix(input, "@"))
	if raw == "" {
		return "", false
	}
	if strings.Contains(raw, "/") || strings.Contains(raw, " ") {
		return "", false
	}
	for _, ch := range raw {
		if (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '_' {
			continue
		}
		return "", false
	}
	return raw, true
}

// normalizeEvents normalizes events.
func normalizeEvents(items []*EventData) []*EventData {
	out := make([]*EventData, 0, len(items))
	for _, item := range items {
		if item == nil {
			continue
		}
		out = append(out, item)
	}
	sort.SliceStable(out, func(i, j int) bool {
		li := out[i].DateTime
		lj := out[j].DateTime
		switch {
		case li == nil && lj == nil:
			return false
		case li == nil:
			return false
		case lj == nil:
			return true
		default:
			return li.After(*lj)
		}
	})
	return out
}
