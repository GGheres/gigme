package parsers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"net/url"
	"strings"
	"time"

	"gigme/backend/internal/eventparser/core"
	"gigme/backend/internal/eventparser/extract"

	"github.com/PuerkitoBio/goquery"
)

type WebParser struct {
	fetcher core.Fetcher
	logger  *slog.Logger
}

func NewWebParser(fetcher core.Fetcher, logger *slog.Logger) *WebParser {
	if logger == nil {
		logger = slog.Default()
	}
	return &WebParser{fetcher: fetcher, logger: logger}
}

func (p *WebParser) Parse(ctx context.Context, input string) (*core.EventData, error) {
	if p == nil || p.fetcher == nil {
		return nil, fmt.Errorf("web parser is not configured")
	}
	pageURL := normalizeURL(input)
	body, status, err := p.fetcher.Get(ctx, pageURL, nil)
	if err != nil {
		return nil, err
	}
	if status >= http.StatusBadRequest {
		return nil, fmt.Errorf("web fetch failed: status %d", status)
	}
	doc, err := goquery.NewDocumentFromReader(bytes.NewReader(body))
	if err != nil {
		return nil, err
	}

	if fromJSONLD := parseJSONLDEvent(doc); fromJSONLD != nil {
		fromJSONLD.Links = extract.MergeLinks(fromJSONLD.Links, collectDocLinks(doc, pageURL))
		return fromJSONLD, nil
	}

	fallback := parseFallbackWebEvent(doc, pageURL)
	if eventScore(fallback) == 0 {
		text := extract.NormalizeText(doc.Text())
		if len(text) < 80 && doc.Find("script").Length() > 10 {
			return nil, &core.DynamicContentError{
				Source: core.SourceWeb,
				URL:    pageURL,
				Hint:   "page appears JS-rendered. Consider BrowserFetcher integration",
			}
		}
		return nil, fmt.Errorf("web parser: no event fields extracted")
	}
	return fallback, nil
}

func parseJSONLDEvent(doc *goquery.Document) *core.EventData {
	best := &core.EventData{}
	bestScore := 0
	doc.Find(`script[type="application/ld+json"]`).Each(func(_ int, script *goquery.Selection) {
		raw := strings.TrimSpace(script.Text())
		if raw == "" {
			return
		}
		var payload interface{}
		if err := json.Unmarshal([]byte(raw), &payload); err != nil {
			return
		}
		for _, obj := range collectJSONObjects(payload) {
			candidate := eventFromJSONLDMap(obj)
			score := eventScore(candidate)
			if score > bestScore {
				best = candidate
				bestScore = score
			}
		}
	})
	if bestScore == 0 {
		return nil
	}
	return best
}

func collectJSONObjects(payload interface{}) []map[string]interface{} {
	out := make([]map[string]interface{}, 0)
	switch v := payload.(type) {
	case map[string]interface{}:
		out = append(out, v)
		if graph, ok := v["@graph"]; ok {
			out = append(out, collectJSONObjects(graph)...)
		}
	case []interface{}:
		for _, item := range v {
			out = append(out, collectJSONObjects(item)...)
		}
	}
	return out
}

func eventFromJSONLDMap(m map[string]interface{}) *core.EventData {
	if !isJSONLDEventType(m["@type"]) {
		return nil
	}
	event := &core.EventData{}
	event.Name = stringField(m, "name")
	event.Description = extract.NormalizeText(stringField(m, "description"))
	event.DateTime = parseDateValue(stringField(m, "startDate"))
	event.Location = parseJSONLDLocation(m["location"])
	event.Links = extract.MergeLinks(parseJSONLDLinks(m), extract.ExtractLinks(event.Description))

	if event.DateTime == nil {
		if parsed, _ := extract.ParseDateTime(event.Description); parsed != nil {
			event.DateTime = parsed
		}
	}
	if event.Location == "" {
		event.Location = extract.ExtractLocation(event.Description)
	}
	if event.Name == "" {
		event.Name = extract.GuessName(event.Description)
	}
	if eventScore(event) == 0 {
		return nil
	}
	return event
}

func isJSONLDEventType(value interface{}) bool {
	switch v := value.(type) {
	case string:
		return strings.EqualFold(strings.TrimSpace(v), "event")
	case []interface{}:
		for _, item := range v {
			if s, ok := item.(string); ok && strings.EqualFold(strings.TrimSpace(s), "event") {
				return true
			}
		}
	}
	return false
}

func parseJSONLDLocation(value interface{}) string {
	switch v := value.(type) {
	case string:
		return strings.TrimSpace(v)
	case map[string]interface{}:
		name := stringField(v, "name")
		address := ""
		switch addr := v["address"].(type) {
		case string:
			address = strings.TrimSpace(addr)
		case map[string]interface{}:
			parts := []string{
				stringField(addr, "streetAddress"),
				stringField(addr, "addressLocality"),
				stringField(addr, "addressRegion"),
				stringField(addr, "addressCountry"),
			}
			filtered := make([]string, 0, len(parts))
			for _, p := range parts {
				if strings.TrimSpace(p) != "" {
					filtered = append(filtered, strings.TrimSpace(p))
				}
			}
			address = strings.Join(filtered, ", ")
		}
		if name != "" && address != "" {
			return name + ", " + address
		}
		if name != "" {
			return name
		}
		return address
	}
	return ""
}

func parseJSONLDLinks(m map[string]interface{}) []string {
	links := make([]string, 0)
	if v := stringField(m, "url"); v != "" {
		links = append(links, v)
	}
	if offers, ok := m["offers"].(map[string]interface{}); ok {
		if v := stringField(offers, "url"); v != "" {
			links = append(links, v)
		}
	}
	if sameAs, ok := m["sameAs"].([]interface{}); ok {
		for _, item := range sameAs {
			if s, ok := item.(string); ok {
				links = append(links, strings.TrimSpace(s))
			}
		}
	}
	return extract.MergeLinks(links)
}

func parseFallbackWebEvent(doc *goquery.Document, pageURL string) *core.EventData {
	event := &core.EventData{}
	event.Name = extract.NormalizeText(doc.Find("h1").First().Text())
	if event.Name == "" {
		event.Name = extract.NormalizeText(doc.Find("title").First().Text())
	}

	timeNode := doc.Find("time").First()
	if timeNode.Length() > 0 {
		if datetimeAttr, ok := timeNode.Attr("datetime"); ok {
			event.DateTime = parseDateValue(datetimeAttr)
		}
		if event.DateTime == nil {
			event.DateTime = parseDateValue(timeNode.Text())
		}
	}

	addressText := extract.NormalizeText(doc.Find("address").First().Text())
	if addressText == "" {
		addressText = extract.NormalizeText(doc.Find(`[class*="address"], [itemprop="location"]`).First().Text())
	}
	event.Location = addressText

	description := strings.TrimSpace(doc.Find(`meta[name="description"]`).AttrOr("content", ""))
	if description == "" {
		description = strings.TrimSpace(doc.Find(`meta[property="og:description"]`).AttrOr("content", ""))
	}
	if description == "" {
		description = extract.NormalizeText(doc.Find("main p").First().Text())
	}
	if description == "" {
		description = extract.NormalizeText(doc.Find("article p").First().Text())
	}
	if description == "" {
		description = extract.NormalizeText(doc.Find("p").First().Text())
	}
	event.Description = description

	if event.DateTime == nil {
		combined := extract.NormalizeText(strings.Join([]string{event.Name, event.Description, doc.Text()}, "\n"))
		event.DateTime, _ = extract.ParseDateTime(combined)
	}
	if event.Location == "" {
		event.Location = extract.ExtractLocation(strings.Join([]string{event.Description, doc.Text()}, "\n"))
	}
	event.Links = extract.MergeLinks(collectDocLinks(doc, pageURL), extract.ExtractLinks(event.Description))
	return event
}

func collectDocLinks(doc *goquery.Document, pageURL string) []string {
	base, _ := url.Parse(pageURL)
	links := make([]string, 0)
	doc.Find("a[href]").Each(func(_ int, sel *goquery.Selection) {
		raw := strings.TrimSpace(sel.AttrOr("href", ""))
		if raw == "" {
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

func parseDateValue(raw string) *time.Time {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil
	}
	if ts, err := time.Parse(time.RFC3339, raw); err == nil {
		ts = ts.UTC()
		return &ts
	}
	if ts, err := time.ParseInLocation("2006-01-02 15:04", raw, time.UTC); err == nil {
		return &ts
	}
	if ts, err := time.ParseInLocation("2006-01-02", raw, time.UTC); err == nil {
		return &ts
	}
	parsed, _ := extract.ParseDateTime(raw)
	return parsed
}

func stringField(m map[string]interface{}, key string) string {
	if m == nil {
		return ""
	}
	v, ok := m[key]
	if !ok {
		return ""
	}
	s, _ := v.(string)
	return strings.TrimSpace(s)
}
