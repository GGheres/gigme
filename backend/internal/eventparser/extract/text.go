package extract

import (
	"html"
	"regexp"
	"strings"
)

var multiSpaceRE = regexp.MustCompile(`\s+`)

func NormalizeText(s string) string {
	s = html.UnescapeString(s)
	s = strings.ReplaceAll(s, "\r\n", "\n")
	s = strings.ReplaceAll(s, "\r", "\n")
	lines := strings.Split(s, "\n")
	out := make([]string, 0, len(lines))
	for _, line := range lines {
		clean := strings.TrimSpace(multiSpaceRE.ReplaceAllString(line, " "))
		if clean == "" {
			continue
		}
		out = append(out, clean)
	}
	return strings.TrimSpace(strings.Join(out, "\n"))
}

func GuessName(text string) string {
	normalized := NormalizeText(text)
	if normalized == "" {
		return ""
	}
	for _, line := range strings.Split(normalized, "\n") {
		candidate := strings.TrimSpace(line)
		if candidate == "" {
			continue
		}
		if len(candidate) > 120 {
			candidate = candidate[:120]
		}
		return candidate
	}
	return ""
}
