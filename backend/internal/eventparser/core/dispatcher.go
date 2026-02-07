package core

import (
	"context"
	"errors"
	"fmt"
	"net/url"
	"strings"

	"golang.org/x/net/publicsuffix"
)

type Dispatcher struct {
	parsers map[SourceType]Parser
}

func NewDispatcher(parsers map[SourceType]Parser) *Dispatcher {
	cloned := make(map[SourceType]Parser, len(parsers))
	for k, v := range parsers {
		cloned[k] = v
	}
	return &Dispatcher{parsers: cloned}
}

func (d *Dispatcher) ParseEvent(ctx context.Context, input string) (*EventData, error) {
	return d.ParseEventWithSource(ctx, input, SourceAuto)
}

func (d *Dispatcher) ParseEventWithSource(ctx context.Context, input string, explicit SourceType) (*EventData, error) {
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
	return parser.Parse(ctx, normalizedInput)
}

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

func parseHTTPURL(raw string) (*url.URL, bool) {
	u, err := url.Parse(strings.TrimSpace(raw))
	if err != nil || u == nil {
		return nil, false
	}
	if u.Scheme == "" || u.Host == "" {
		return nil, false
	}
	scheme := strings.ToLower(u.Scheme)
	if scheme != "http" && scheme != "https" {
		return nil, false
	}
	return u, true
}

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
