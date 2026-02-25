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

// InstagramParser represents instagram parser.
type InstagramParser struct {
	fetcher core.Fetcher
	logger  *slog.Logger
}

// NewInstagramParser creates instagram parser.
func NewInstagramParser(fetcher core.Fetcher, logger *slog.Logger) *InstagramParser {
	if logger == nil {
		logger = slog.Default()
	}
	return &InstagramParser{fetcher: fetcher, logger: logger}
}

// Parse parses the provided input.
func (p *InstagramParser) Parse(ctx context.Context, input string) (*core.EventData, error) {
	if p == nil || p.fetcher == nil {
		return nil, fmt.Errorf("instagram parser is not configured")
	}
	pageURL := normalizeURL(input)
	body, status, err := p.fetcher.Get(ctx, pageURL, nil)
	if err != nil {
		return nil, err
	}
	lowerBody := strings.ToLower(string(body))
	if status == http.StatusUnauthorized || status == http.StatusForbidden || looksLikeInstagramAuthWall(lowerBody) {
		return nil, &core.AuthRequiredError{
			Source: core.SourceInstagram,
			URL:    pageURL,
			Hint:   "Instagram often blocks unauthenticated scraping. Provide authenticated cookies or use a browser renderer.",
		}
	}
	if status >= http.StatusBadRequest {
		return nil, fmt.Errorf("instagram fetch failed: status %d", status)
	}

	doc, err := goquery.NewDocumentFromReader(bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	name := strings.TrimSpace(doc.Find(`meta[property="og:title"]`).AttrOr("content", ""))
	description := strings.TrimSpace(doc.Find(`meta[property="og:description"]`).AttrOr("content", ""))

	if name == "" && description == "" {
		return nil, &core.DynamicContentError{
			Source: core.SourceInstagram,
			URL:    pageURL,
			Hint:   "Instagram often blocks unauthenticated scraping. Provide authenticated cookies or use a browser renderer.",
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

// looksLikeInstagramAuthWall handles looks like instagram auth wall.
func looksLikeInstagramAuthWall(lowerBody string) bool {
	return strings.Contains(lowerBody, "log in") ||
		strings.Contains(lowerBody, "login") ||
		strings.Contains(lowerBody, "session") ||
		strings.Contains(lowerBody, "instagram.com/accounts/login")
}
