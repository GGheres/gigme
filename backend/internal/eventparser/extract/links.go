package extract

import (
	"regexp"
	"strings"
)

var urlRE = regexp.MustCompile(`https?://[^\s<>"]+`)

func ExtractLinks(text string) []string {
	matches := urlRE.FindAllString(text, -1)
	if len(matches) == 0 {
		return nil
	}
	seen := make(map[string]struct{}, len(matches))
	out := make([]string, 0, len(matches))
	for _, raw := range matches {
		clean := strings.TrimSpace(strings.Trim(raw, ".,);]"))
		if clean == "" {
			continue
		}
		if _, ok := seen[clean]; ok {
			continue
		}
		seen[clean] = struct{}{}
		out = append(out, clean)
	}
	if len(out) == 0 {
		return nil
	}
	return out
}

func MergeLinks(lists ...[]string) []string {
	seen := map[string]struct{}{}
	out := make([]string, 0)
	for _, list := range lists {
		for _, raw := range list {
			link := strings.TrimSpace(raw)
			if link == "" {
				continue
			}
			if _, ok := seen[link]; ok {
				continue
			}
			seen[link] = struct{}{}
			out = append(out, link)
		}
	}
	if len(out) == 0 {
		return nil
	}
	return out
}
