package parsers

import (
	"bytes"
	"context"
	"fmt"
	"html"
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
	htmlnode "golang.org/x/net/html"
)

var (
	tgPhotoStyleURLRE = regexp.MustCompile(`url\(['"]?([^'")]+)['"]?\)`)
	tgMultiSpaceRE    = regexp.MustCompile(`\s+`)
)

// TelegramParser represents telegram parser.
type TelegramParser struct {
	fetcher core.Fetcher
	logger  *slog.Logger
}

// NewTelegramParser creates telegram parser.
func NewTelegramParser(fetcher core.Fetcher, logger *slog.Logger) *TelegramParser {
	if logger == nil {
		logger = slog.Default()
	}
	return &TelegramParser{fetcher: fetcher, logger: logger}
}

// Parse parses the provided input.
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

// ParseMany parses many.
func (p *TelegramParser) ParseMany(ctx context.Context, input string) ([]*core.EventData, error) {
	if p == nil || p.fetcher == nil {
		return nil, fmt.Errorf("telegram parser is not configured")
	}
	spec, err := normalizeTelegramInput(input)
	if err != nil {
		return nil, err
	}

	now := time.Now().UTC()
	from := now.Add(-24 * time.Hour)
	items := make([]*core.EventData, 0)
	staleFallback := make([]*core.EventData, 0)
	seenPosts := make(map[int64]struct{})
	currentURL := spec.PageURL
	maxPages := 8
	if spec.IsSinglePost {
		maxPages = 1
	}
	targetFound := false
	for pageIdx := 0; pageIdx < maxPages; pageIdx++ {
		body, status, err := p.fetcher.Get(ctx, currentURL, nil)
		if err != nil {
			if len(items) > 0 {
				p.logger.Warn("telegram pagination fetch failed; returning partial result",
					"url", currentURL,
					"page", pageIdx,
					"error", err,
					"parsed_events", len(items),
				)
				break
			}
			return nil, err
		}
		if status >= http.StatusBadRequest {
			if len(items) > 0 {
				p.logger.Warn("telegram pagination returned bad status; returning partial result",
					"url", currentURL,
					"page", pageIdx,
					"status", status,
					"parsed_events", len(items),
				)
				break
			}
			return nil, fmt.Errorf("telegram fetch failed: status %d", status)
		}
		doc, err := goquery.NewDocumentFromReader(bytes.NewReader(body))
		if err != nil {
			if len(items) > 0 {
				p.logger.Warn("telegram pagination html parse failed; returning partial result",
					"url", currentURL,
					"page", pageIdx,
					"error", err,
					"parsed_events", len(items),
				)
				break
			}
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
				if spec.IsSinglePost && postID != spec.TargetPostID {
					return
				}
				if _, exists := seenPosts[postID]; exists {
					return
				}
				seenPosts[postID] = struct{}{}
				if spec.IsSinglePost {
					targetFound = true
				}
				if !hasPostID || postID < minPostID {
					minPostID = postID
					hasPostID = true
				}
			}

			publishedAt := parseTelegramMessageDate(message)
			isOlderThanWindow := false
			if publishedAt != nil && !spec.IsSinglePost {
				pubUTC := publishedAt.UTC()
				if pubUTC.Before(from) {
					hasOlder = true
					isOlderThanWindow = true
				}
				if pubUTC.After(now.Add(15 * time.Minute)) {
					return
				}
			}

			text := extractTelegramMessageText(message.Find("div.tgme_widget_message_text").First())
			if text == "" {
				return
			}

			hrefs := collectHrefs(message, currentURL)
			media := collectTelegramMediaLinks(message, currentURL)
			candidate := buildEventFromText(text, hrefs, media)
			candidate.Links = extract.MergeLinks(candidate.Links, media)
			if spec.IsSinglePost {
				candidate.Links = filterTelegramSinglePostLinks(candidate.Links, spec.Channel, spec.TargetPostID)
			}
			if eventScore(candidate) == 0 {
				return
			}
			if candidate.DateTime == nil && publishedAt != nil {
				// Fallback to message timestamp when textual date is missing.
				t := publishedAt.UTC()
				candidate.DateTime = &t
			}
			if isOlderThanWindow && !spec.IsSinglePost {
				// Keep a fallback list from the first page when the last-24h window is empty.
				if pageIdx == 0 {
					staleFallback = append(staleFallback, candidate)
				}
				return
			}
			pageItems = append(pageItems, candidate)
		})
		items = append(items, pageItems...)

		if len(items) == 0 && pageIdx == 0 && !spec.IsSinglePost {
			// Fallback for older/minimal Telegram layouts without wrappers.
			doc.Find("div.tgme_widget_message_text").Each(func(_ int, sel *goquery.Selection) {
				text := extractTelegramMessageText(sel)
				if text == "" {
					return
				}
				items = append(items, buildEventFromText(text, collectHrefs(sel, spec.PageURL)))
			})
			if len(items) == 0 {
				fallbackText := extract.NormalizeText(doc.Text())
				if fallbackText != "" {
					items = append(items, buildEventFromText(fallbackText))
				}
			}
		}

		if spec.IsSinglePost {
			break
		}
		if hasOlder {
			break
		}
		if !hasPostID || minPostID <= 1 {
			break
		}
		nextURL := telegramBeforeURL(spec.PageURL, minPostID)
		if nextURL == currentURL {
			break
		}
		currentURL = nextURL
	}
	if spec.IsSinglePost {
		if len(items) > 0 {
			return items, nil
		}
		fallback, err := p.parseDirectPostFallback(ctx, spec.DirectPostURL)
		if err != nil {
			return nil, err
		}
		if fallback != nil {
			return []*core.EventData{fallback}, nil
		}
		if targetFound {
			return nil, fmt.Errorf("telegram parser: target post has no parseable content")
		}
		return nil, fmt.Errorf("telegram parser: post %d not found in channel %s", spec.TargetPostID, spec.Channel)
	}
	if len(items) == 0 && len(staleFallback) > 0 {
		const maxFallback = 20
		if len(staleFallback) > maxFallback {
			staleFallback = staleFallback[:maxFallback]
		}
		p.logger.Info("telegram parser window fallback applied",
			"url", spec.PageURL,
			"fallback_events", len(staleFallback),
		)
		return staleFallback, nil
	}
	return items, nil
}

// telegramInputSpec represents telegram input spec.
type telegramInputSpec struct {
	Channel       string
	PageURL       string
	DirectPostURL string
	TargetPostID  int64
	IsSinglePost  bool
}

// normalizeTelegramInput normalizes telegram input.
func normalizeTelegramInput(input string) (telegramInputSpec, error) {
	trimmed := strings.TrimSpace(strings.TrimPrefix(input, "@"))
	if trimmed == "" {
		return telegramInputSpec{}, &core.UnsupportedInputError{Input: input, Hint: "telegram channel is empty"}
	}
	buildSpec := func(channel string, postID int64) (telegramInputSpec, error) {
		channel = strings.TrimSpace(channel)
		if !isValidTelegramChannel(channel) {
			return telegramInputSpec{}, &core.UnsupportedInputError{Input: input, Hint: "telegram channel name is invalid"}
		}
		spec := telegramInputSpec{
			Channel: channel,
			PageURL: "https://t.me/s/" + channel,
		}
		if postID > 0 {
			spec.IsSinglePost = true
			spec.TargetPostID = postID
			spec.PageURL = fmt.Sprintf("https://t.me/s/%s/%d", channel, postID)
			spec.DirectPostURL = fmt.Sprintf("https://t.me/%s/%d", channel, postID)
		}
		return spec, nil
	}
	if strings.HasPrefix(trimmed, "http://") || strings.HasPrefix(trimmed, "https://") {
		u, err := url.Parse(trimmed)
		if err != nil || u.Hostname() == "" {
			return telegramInputSpec{}, &core.UnsupportedInputError{Input: input, Hint: "invalid telegram URL"}
		}
		host := strings.ToLower(strings.TrimSpace(u.Hostname()))
		if host != "t.me" && host != "telegram.me" && !strings.HasSuffix(host, ".t.me") && !strings.HasSuffix(host, ".telegram.me") {
			return telegramInputSpec{}, &core.UnsupportedInputError{Input: input, Hint: "expected t.me URL"}
		}
		path := strings.Trim(u.Path, "/")
		if path == "" {
			return telegramInputSpec{}, &core.UnsupportedInputError{Input: input, Hint: "telegram URL path is empty"}
		}
		parts := strings.Split(path, "/")
		switch {
		case parts[0] == "s":
			if len(parts) < 2 {
				return telegramInputSpec{}, &core.UnsupportedInputError{Input: input, Hint: "telegram channel is missing"}
			}
			channel := parts[1]
			if len(parts) >= 3 {
				postID, err := strconv.ParseInt(strings.TrimSpace(parts[2]), 10, 64)
				if err == nil && postID > 0 {
					return buildSpec(channel, postID)
				}
			}
			return buildSpec(channel, 0)
		default:
			channel := parts[0]
			if len(parts) >= 2 {
				postID, err := strconv.ParseInt(strings.TrimSpace(parts[1]), 10, 64)
				if err == nil && postID > 0 {
					return buildSpec(channel, postID)
				}
			}
			return buildSpec(channel, 0)
		}
	}
	if strings.Contains(trimmed, "/") || strings.Contains(trimmed, " ") {
		return telegramInputSpec{}, &core.UnsupportedInputError{Input: input, Hint: "telegram channel name is invalid"}
	}
	return buildSpec(trimmed, 0)
}

// collectHrefs handles collect hrefs.
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

// collectTelegramMediaLinks handles collect telegram media links.
func collectTelegramMediaLinks(sel *goquery.Selection, pageURL string) []string {
	base, _ := url.Parse(pageURL)
	media := make([]string, 0)
	sel.Find("a.tgme_widget_message_photo_wrap, a.tgme_widget_message_video_player i.tgme_widget_message_video_thumb, a.tgme_widget_message_photo_wrap img[src], a.tgme_widget_message_video_player img[src]").Each(func(_ int, node *goquery.Selection) {
		style := strings.TrimSpace(node.AttrOr("style", ""))
		if style != "" {
			match := tgPhotoStyleURLRE.FindStringSubmatch(style)
			if len(match) == 2 {
				if resolved := resolveHTTPURL(base, match[1]); resolved != "" {
					media = append(media, resolved)
					return
				}
			}
		}
		src := strings.TrimSpace(node.AttrOr("src", ""))
		if src != "" {
			if resolved := resolveHTTPURL(base, src); resolved != "" {
				media = append(media, resolved)
				return
			}
		}
		if href, ok := node.Attr("href"); ok {
			if resolved := resolveHTTPURL(base, href); isLikelyImageURL(resolved) {
				media = append(media, resolved)
			}
		}
	})
	return extract.MergeLinks(media)
}

// isLikelyImageURL reports whether likely image u r l condition is met.
func isLikelyImageURL(raw string) bool {
	u, err := url.Parse(strings.TrimSpace(raw))
	if err != nil || u == nil {
		return false
	}
	path := strings.ToLower(strings.TrimSpace(u.Path))
	return strings.HasSuffix(path, ".jpg") ||
		strings.HasSuffix(path, ".jpeg") ||
		strings.HasSuffix(path, ".png") ||
		strings.HasSuffix(path, ".webp") ||
		strings.HasSuffix(path, ".gif")
}

// resolveHTTPURL handles resolve h t t p u r l.
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

// parseTelegramMessageDate parses telegram message date.
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

// parseDirectPostFallback parses direct post fallback.
func (p *TelegramParser) parseDirectPostFallback(ctx context.Context, directURL string) (*core.EventData, error) {
	directURL = strings.TrimSpace(directURL)
	if directURL == "" {
		return nil, nil
	}
	body, status, err := p.fetcher.Get(ctx, directURL, nil)
	if err != nil {
		return nil, err
	}
	if status >= http.StatusBadRequest {
		return nil, fmt.Errorf("telegram direct post fetch failed: status %d", status)
	}
	doc, err := goquery.NewDocumentFromReader(bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	description := extract.NormalizeText(doc.Find(`meta[property="og:description"]`).AttrOr("content", ""))
	title := extract.NormalizeText(doc.Find(`meta[property="og:title"]`).AttrOr("content", ""))
	if description == "" && title == "" {
		return nil, nil
	}
	text := description
	if text == "" {
		text = title
	}
	event := buildEventFromText(text)
	if strings.TrimSpace(event.Name) == "" && title != "" {
		event.Name = title
	}
	if strings.TrimSpace(event.Description) == "" {
		event.Description = text
	}
	image := strings.TrimSpace(doc.Find(`meta[property="og:image"]`).AttrOr("content", ""))
	event.Links = extract.MergeLinks(event.Links, []string{directURL, image})
	return event, nil
}

// filterTelegramSinglePostLinks handles filter telegram single post links.
func filterTelegramSinglePostLinks(links []string, channel string, targetPostID int64) []string {
	if len(links) == 0 || channel == "" || targetPostID <= 0 {
		return links
	}
	out := make([]string, 0, len(links))
	for _, raw := range links {
		link := strings.TrimSpace(raw)
		if link == "" {
			continue
		}
		u, err := url.Parse(link)
		if err != nil || u == nil {
			out = append(out, link)
			continue
		}
		host := strings.ToLower(strings.TrimSpace(u.Hostname()))
		isTelegramHost := host == "t.me" || host == "telegram.me" || strings.HasSuffix(host, ".t.me") || strings.HasSuffix(host, ".telegram.me")
		if !isTelegramHost {
			out = append(out, link)
			continue
		}
		parts := strings.Split(strings.Trim(u.Path, "/"), "/")
		if len(parts) >= 2 && strings.EqualFold(parts[0], channel) {
			if postID, err := strconv.ParseInt(parts[1], 10, 64); err == nil && postID > 0 && postID != targetPostID {
				continue
			}
		}
		out = append(out, link)
	}
	return extract.MergeLinks(out)
}

// isValidTelegramChannel reports whether valid telegram channel condition is met.
func isValidTelegramChannel(channel string) bool {
	if channel == "" {
		return false
	}
	for _, ch := range channel {
		if (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '_' {
			continue
		}
		return false
	}
	return true
}

// extractTelegramMessageText extracts telegram message text.
func extractTelegramMessageText(sel *goquery.Selection) string {
	if sel == nil || sel.Length() == 0 {
		return ""
	}
	var b strings.Builder
	for _, node := range sel.Nodes {
		appendTelegramTextNode(&b, node)
	}
	return normalizeTelegramMultilineText(b.String())
}

// appendTelegramTextNode handles append telegram text node.
func appendTelegramTextNode(b *strings.Builder, node *htmlnode.Node) {
	if b == nil || node == nil {
		return
	}
	switch node.Type {
	case htmlnode.TextNode:
		b.WriteString(node.Data)
		return
	case htmlnode.ElementNode:
		tag := strings.ToLower(strings.TrimSpace(node.Data))
		if tag == "br" {
			appendLineBreak(b, true)
			return
		}
		isBlock := isBlockTag(tag)
		if isBlock {
			appendLineBreak(b, false)
		}
		for child := node.FirstChild; child != nil; child = child.NextSibling {
			appendTelegramTextNode(b, child)
		}
		if isBlock {
			appendLineBreak(b, false)
		}
		return
	default:
		for child := node.FirstChild; child != nil; child = child.NextSibling {
			appendTelegramTextNode(b, child)
		}
	}
}

// isBlockTag reports whether block tag condition is met.
func isBlockTag(tag string) bool {
	switch tag {
	case "p", "div", "li", "ul", "ol", "blockquote":
		return true
	default:
		return false
	}
}

// appendLineBreak handles append line break.
func appendLineBreak(b *strings.Builder, allowDouble bool) {
	if b == nil || b.Len() == 0 {
		return
	}
	current := b.String()
	if strings.HasSuffix(current, "\n\n") {
		return
	}
	if strings.HasSuffix(current, "\n") {
		if allowDouble {
			b.WriteByte('\n')
		}
		return
	}
	b.WriteByte('\n')
}

// normalizeTelegramMultilineText normalizes telegram multiline text.
func normalizeTelegramMultilineText(raw string) string {
	raw = html.UnescapeString(raw)
	raw = strings.ReplaceAll(raw, "\r\n", "\n")
	raw = strings.ReplaceAll(raw, "\r", "\n")
	lines := strings.Split(raw, "\n")
	out := make([]string, 0, len(lines))
	for _, line := range lines {
		line = strings.ReplaceAll(line, "\u00a0", " ")
		clean := strings.TrimSpace(tgMultiSpaceRE.ReplaceAllString(line, " "))
		if clean == "" {
			if len(out) == 0 || out[len(out)-1] == "" {
				continue
			}
			out = append(out, "")
			continue
		}
		out = append(out, clean)
	}
	result := strings.TrimSpace(strings.Join(out, "\n"))
	return extract.NormalizeText(result)
}

// parseTelegramPostID parses telegram post i d.
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

// telegramBeforeURL handles telegram before u r l.
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
