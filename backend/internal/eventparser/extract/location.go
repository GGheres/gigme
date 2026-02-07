package extract

import (
	"strings"
)

var locationKeywords = []string{
	"location:",
	"place:",
	"venue:",
	"address:",
	"место:",
	"адрес:",
	"локация:",
}

func ExtractLocation(text string) string {
	normalized := NormalizeText(text)
	if normalized == "" {
		return ""
	}
	lines := strings.Split(normalized, "\n")
	for _, line := range lines {
		lower := strings.ToLower(strings.TrimSpace(line))
		for _, kw := range locationKeywords {
			if strings.Contains(lower, kw) {
				parts := strings.SplitN(line, ":", 2)
				if len(parts) == 2 {
					return strings.TrimSpace(parts[1])
				}
				return strings.TrimSpace(line)
			}
		}
	}
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "📍") {
			return strings.TrimSpace(strings.TrimPrefix(line, "📍"))
		}
	}
	return ""
}
