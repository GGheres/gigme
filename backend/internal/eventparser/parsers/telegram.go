package parsers

import (
	"bytes"
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"

	"gigme/backend/internal/eventparser/core"
	"gigme/backend/internal/eventparser/extract"

	"github.com/PuerkitoBio/goquery"
)

var tgPhotoStyleURLRE = regexp.MustCompile(`url\(['"]?([^'")]+)['"]?\)`)

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
	events, err := p.ParseMany(ctx, input)
	if err != nil {
		return nil, err
	}
	if len(events) == 0 {
		return nil, fmt.Errorf("telegram parser: no messages parsed")
	}
	return events[0], nil
}

func (p *TelegramParser) ParseMany(ctx context.Context, input string) ([]*core.EventData, error) {
	if p == nil || p.fetcher == nil {
		return nil, fmt.Errorf("telegram parser is not configured")
	}
	pageURL, err := normalizeTelegramInput(input)
	if err != nil {
		return nil, err
	}

	now := time.Now().UTC()
	from := now.Add(-24 * time.Hour)
	items := make([]*core.EventData, 0)
	seenPosts := make(map[int64]struct{})
	currentURL := pageURL
	const maxPages = 8
	for pageIdx := 0; pageIdx < maxPages; pageIdx++ {
		body, status, err := p.fetcher.Get(ctx, currentURL, nil)
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

		pageItems := make([]*core.EventData, 0)
		var minPostID int64
		var hasPostID bool
		hasOlder := false
		doc.Find("div.tgme_widget_message_wrap").Each(func(_ int, wrap *goquery.Selection) {
			message := wrap.Find("div.tgme_widget_message").First()
			if message.Length() == 0 {
				message = wrap
			}
			postID := parseTelegramPostID(message.AttrOr("data-post", ""))
			if postID > 0 {
				if _, exists := seenPosts[postID]; exists {
					return
				}
				seenPosts[postID] = struct{}{}
				if !hasPostID || postID < minPostID {
					minPostID = postID
					hasPostID = true
				}
			}

			publishedAt := parseTelegramMessageDate(message)
			if publishedAt != nil {
				pubUTC := publishedAt.UTC()
				if pubUTC.Before(from) {
					hasOlder = true
					return
				}
				if pubUTC.After(now.Add(15 * time.Minute)) {
					return
				}
			}

			text := extract.NormalizeText(message.Find("div.tgme_widget_message_text").First().Text())
			if text == "" {
				return
			}

			hrefs := collectHrefs(message, pageURL)
			media := collectTelegramMediaLinks(message, pageURL)
			candidate := buildEventFromText(text, hrefs, media)
			candidate.Links = extract.MergeLinks(candidate.Links, media)
			if eventScore(candidate) == 0 {
				return
			}
			if candidate.DateTime == nil && publishedAt != nil {
				// Fallback to message timestamp when textual date is missing.
				t := publishedAt.UTC()
				candidate.DateTime = &t
			}
			pageItems = append(pageItems, candidate)
		})
		items = append(items, pageItems...)

		if len(items) == 0 && pageIdx == 0 {
			// Fallback for older/minimal Telegram layouts without wrappers.
			doc.Find("div.tgme_widget_message_text").Each(func(_ int, sel *goquery.Selection) {
				text := extract.NormalizeText(sel.Text())
				if text == "" {
					return
				}
				items = append(items, buildEventFromText(text, collectHrefs(sel, pageURL)))
			})
			if len(items) == 0 {
				fallbackText := extract.NormalizeText(doc.Text())
				if fallbackText != "" {
					items = append(items, buildEventFromText(fallbackText))
				}
			}
		}

		if hasOlder {
			break
		}
		if !hasPostID || minPostID <= 1 {
			break
		}
		nextURL := telegramBeforeURL(pageURL, minPostID)
		if nextURL == currentURL {
			break
		}
		currentURL = nextURL
	}

	return items, nil
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

func collectTelegramMediaLinks(sel *goquery.Selection, pageURL string) []string {
	base, _ := url.Parse(pageURL)
	media := make([]string, 0)
	sel.Find("a.tgme_widget_message_photo_wrap").Each(func(_ int, a *goquery.Selection) {
		if href, ok := a.Attr("href"); ok {
			if resolved := resolveHTTPURL(base, href); resolved != "" {
				media = append(media, resolved)
			}
		}
		style := strings.TrimSpace(a.AttrOr("style", ""))
		if style != "" {
			match := tgPhotoStyleURLRE.FindStringSubmatch(style)
			if len(match) == 2 {
				if resolved := resolveHTTPURL(base, match[1]); resolved != "" {
					media = append(media, resolved)
				}
			}
		}
	})
	sel.Find("img[src]").Each(func(_ int, img *goquery.Selection) {
		src := strings.TrimSpace(img.AttrOr("src", ""))
		if resolved := resolveHTTPURL(base, src); resolved != "" {
			media = append(media, resolved)
		}
	})
	return extract.MergeLinks(media)
}

func resolveHTTPURL(base *url.URL, raw string) string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return ""
	}
	u, err := url.Parse(raw)
	if err != nil {
		return ""
	}
	if base != nil {
		u = base.ResolveReference(u)
	}
	if u.Scheme != "http" && u.Scheme != "https" {
		return ""
	}
	return u.String()
}

func parseTelegramMessageDate(message *goquery.Selection) *time.Time {
	timeNode := message.Find("a.tgme_widget_message_date time").First()
	if timeNode.Length() == 0 {
		timeNode = message.Find("time").First()
	}
	if timeNode.Length() == 0 {
		return nil
	}
	raw := strings.TrimSpace(timeNode.AttrOr("datetime", ""))
	if raw == "" {
		raw = strings.TrimSpace(timeNode.Text())
	}
	if raw == "" {
		return nil
	}
	if ts, err := time.Parse(time.RFC3339, raw); err == nil {
		return &ts
	}
	if ts, err := time.Parse(time.RFC3339Nano, raw); err == nil {
		return &ts
	}
	if ts, err := extract.ParseDateTime(raw); err == nil && ts != nil {
		return ts
	}
	return nil
}

func parseTelegramPostID(dataPost string) int64 {
	dataPost = strings.TrimSpace(dataPost)
	if dataPost == "" {
		return 0
	}
	parts := strings.Split(dataPost, "/")
	if len(parts) != 2 {
		return 0
	}
	id, err := strconv.ParseInt(strings.TrimSpace(parts[1]), 10, 64)
	if err != nil || id <= 0 {
		return 0
	}
	return id
}

func telegramBeforeURL(baseURL string, before int64) string {
	if before <= 0 {
		return baseURL
	}
	u, err := url.Parse(baseURL)
	if err != nil {
		return baseURL
	}
	q := u.Query()
	q.Set("before", strconv.FormatInt(before, 10))
	u.RawQuery = q.Encode()
	return u.String()
}
