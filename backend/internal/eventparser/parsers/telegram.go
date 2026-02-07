package parsers

import (
	"bytes"
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"net/url"
	"strings"

	"gigme/backend/internal/eventparser/core"
	"gigme/backend/internal/eventparser/extract"

	"github.com/PuerkitoBio/goquery"
)

type TelegramParser struct {
	fetcher core.Fetcher
	logger  *slog.Logger
}

func NewTelegramParser(fetcher core.Fetcher, logger *slog.Logger) *TelegramParser {
	if logger == nil {
		logger = slog.Default()
	}
	return &TelegramParser{fetcher: fetcher, logger: logger}
}

func (p *TelegramParser) Parse(ctx context.Context, input string) (*core.EventData, error) {
	if p == nil || p.fetcher == nil {
		return nil, fmt.Errorf("telegram parser is not configured")
	}
	pageURL, err := normalizeTelegramInput(input)
	if err != nil {
		return nil, err
	}

	body, status, err := p.fetcher.Get(ctx, pageURL, nil)
	if err != nil {
		return nil, err
	}
	if status >= http.StatusBadRequest {
		return nil, fmt.Errorf("telegram fetch failed: status %d", status)
	}
	doc, err := goquery.NewDocumentFromReader(bytes.NewReader(body))
	if err != nil {
		return nil, err
	}

	best := &core.EventData{}
	bestScore := 0
	doc.Find("div.tgme_widget_message_text").Each(func(_ int, sel *goquery.Selection) {
		text := extract.NormalizeText(sel.Text())
		if text == "" {
			return
		}
		hrefs := collectHrefs(sel, pageURL)
		candidate := buildEventFromText(text, hrefs)
		score := eventScore(candidate)
		if score > bestScore {
			best = candidate
			bestScore = score
		}
	})

	if bestScore == 0 {
		fallbackText := extract.NormalizeText(doc.Text())
		if fallbackText == "" {
			return nil, fmt.Errorf("telegram parser: no message text found")
		}
		best = buildEventFromText(fallbackText)
	}
	return best, nil
}

func normalizeTelegramInput(input string) (string, error) {
	trimmed := strings.TrimSpace(strings.TrimPrefix(input, "@"))
	if trimmed == "" {
		return "", &core.UnsupportedInputError{Input: input, Hint: "telegram channel is empty"}
	}
	if strings.HasPrefix(trimmed, "http://") || strings.HasPrefix(trimmed, "https://") {
		u, err := url.Parse(trimmed)
		if err != nil || u.Hostname() == "" {
			return "", &core.UnsupportedInputError{Input: input, Hint: "invalid telegram URL"}
		}
		if u.Hostname() != "t.me" {
			return "", &core.UnsupportedInputError{Input: input, Hint: "expected t.me URL"}
		}
		if !strings.HasPrefix(u.Path, "/s/") {
			u.Path = "/s" + strings.TrimPrefix(u.Path, "/")
			if !strings.HasPrefix(u.Path, "/s/") {
				u.Path = "/s/" + strings.TrimPrefix(strings.TrimPrefix(u.Path, "/s"), "/")
			}
		}
		return u.String(), nil
	}
	if strings.Contains(trimmed, "/") || strings.Contains(trimmed, " ") {
		return "", &core.UnsupportedInputError{Input: input, Hint: "telegram channel name is invalid"}
	}
	return "https://t.me/s/" + trimmed, nil
}

func collectHrefs(sel *goquery.Selection, pageURL string) []string {
	base, _ := url.Parse(pageURL)
	links := make([]string, 0)
	sel.Find("a[href]").Each(func(_ int, a *goquery.Selection) {
		raw, ok := a.Attr("href")
		if !ok || strings.TrimSpace(raw) == "" {
			return
		}
		u, err := url.Parse(raw)
		if err != nil {
			return
		}
		if base != nil {
			u = base.ResolveReference(u)
		}
		if u.Scheme != "http" && u.Scheme != "https" {
			return
		}
		links = append(links, u.String())
	})
	return extract.MergeLinks(links)
}
