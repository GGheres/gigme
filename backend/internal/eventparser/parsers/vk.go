package parsers

import (
	"bytes"
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"strings"

	"gigme/backend/internal/eventparser/core"
	"gigme/backend/internal/eventparser/extract"

	"github.com/PuerkitoBio/goquery"
)

type VKParser struct {
	fetcher core.Fetcher
	logger  *slog.Logger
}

func NewVKParser(fetcher core.Fetcher, logger *slog.Logger) *VKParser {
	if logger == nil {
		logger = slog.Default()
	}
	return &VKParser{fetcher: fetcher, logger: logger}
}

func (p *VKParser) Parse(ctx context.Context, input string) (*core.EventData, error) {
	if p == nil || p.fetcher == nil {
		return nil, fmt.Errorf("vk parser is not configured")
	}
	pageURL := normalizeURL(input)
	body, status, err := p.fetcher.Get(ctx, pageURL, nil)
	if err != nil {
		return nil, err
	}
	lowerBody := strings.ToLower(string(body))
	if status == http.StatusUnauthorized || status == http.StatusForbidden || looksLikeVKAuthWall(lowerBody) {
		return nil, &core.AuthRequiredError{
			Source: core.SourceVK,
			URL:    pageURL,
			Hint:   "VK page requires authentication for full content.",
		}
	}
	if status >= http.StatusBadRequest {
		return nil, fmt.Errorf("vk fetch failed: status %d", status)
	}

	doc, err := goquery.NewDocumentFromReader(bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	name := strings.TrimSpace(doc.Find(`meta[property="og:title"]`).AttrOr("content", ""))
	if name == "" {
		name = extract.NormalizeText(doc.Find("title").First().Text())
	}
	description := strings.TrimSpace(doc.Find(`meta[property="og:description"]`).AttrOr("content", ""))
	if description == "" {
		description = extract.NormalizeText(doc.Find(`meta[name="description"]`).AttrOr("content", ""))
	}

	if name == "" && description == "" {
		return nil, &core.DynamicContentError{
			Source: core.SourceVK,
			URL:    pageURL,
			Hint:   "VK content may be dynamically rendered. Use browser renderer if needed.",
		}
	}

	normalized := extract.NormalizeText(description)
	date, _ := extract.ParseDateTime(normalized)
	location := extract.ExtractLocation(normalized)
	links := extract.MergeLinks(extract.ExtractLinks(normalized), collectDocLinks(doc, pageURL))

	return &core.EventData{
		Name:        name,
		DateTime:    date,
		Location:    location,
		Description: normalized,
		Links:       links,
	}, nil
}

func looksLikeVKAuthWall(lowerBody string) bool {
	return strings.Contains(lowerBody, "login.vk.com") ||
		strings.Contains(lowerBody, "id=\"login_form\"") ||
		strings.Contains(lowerBody, "войдите")
}
