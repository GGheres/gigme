package parsers

import (
	"net/url"
	"strings"

	"gigme/backend/internal/eventparser/core"
	"gigme/backend/internal/eventparser/extract"
)

func buildEventFromText(text string, links ...[]string) *core.EventData {
	normalized := extract.NormalizeText(text)
	name := extract.GuessName(normalized)
	date, _ := extract.ParseDateTime(normalized)
	location := extract.ExtractLocation(normalized)
	allLinks := make([][]string, 0, len(links)+1)
	allLinks = append(allLinks, extract.ExtractLinks(normalized))
	allLinks = append(allLinks, links...)
	return &core.EventData{
		Name:        name,
		DateTime:    date,
		Location:    location,
		Description: normalized,
		Links:       extract.MergeLinks(allLinks...),
	}
}

func eventScore(event *core.EventData) int {
	if event == nil {
		return 0
	}
	score := 0
	if strings.TrimSpace(event.Name) != "" {
		score++
	}
	if event.DateTime != nil {
		score += 2
	}
	if strings.TrimSpace(event.Location) != "" {
		score++
	}
	if strings.TrimSpace(event.Description) != "" {
		score++
	}
	if len(event.Links) > 0 {
		score++
	}
	return score
}

func normalizeURL(input string) string {
	trimmed := strings.TrimSpace(input)
	u, err := url.Parse(trimmed)
	if err != nil || u == nil {
		return trimmed
	}
	if u.Scheme == "" {
		u.Scheme = "https"
	}
	return u.String()
}
