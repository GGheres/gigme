package extract

import (
	"fmt"
	"regexp"
	"sort"
	"strings"
	"time"
)

var (
	ruMonthToEN = map[string]string{
		"января":   "january",
		"январь":   "january",
		"февраля":  "february",
		"февраль":  "february",
		"марта":    "march",
		"март":     "march",
		"апреля":   "april",
		"апрель":   "april",
		"мая":      "may",
		"май":      "may",
		"июня":     "june",
		"июнь":     "june",
		"июля":     "july",
		"июль":     "july",
		"августа":  "august",
		"август":   "august",
		"сентября": "september",
		"сентябрь": "september",
		"октября":  "october",
		"октябрь":  "october",
		"ноября":   "november",
		"ноябрь":   "november",
		"декабря":  "december",
		"декабрь":  "december",
	}

	enMonthPattern = `(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t|tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)`
	ruMonthPattern = `(?:январ[ья]|феврал[ья]|март[а]?|апрел[ья]|ма[йя]|июн[ья]|июл[ья]|август[а]?|сентябр[ья]|октябр[ья]|ноябр[ья]|декабр[ья])`

	dateCandidatePatterns = []*regexp.Regexp{
		regexp.MustCompile(`(?i)\b\d{1,2}[./-]\d{1,2}[./-]\d{2,4}(?:\s*(?:в|at)?\s*\d{1,2}[:.]\d{2}(?:\s?(?:am|pm))?)?\b`),
		regexp.MustCompile(`(?i)\b\d{1,2}\s+(?:` + enMonthPattern + `|` + ruMonthPattern + `)(?:\s+\d{2,4})?(?:\s*(?:в|at)?\s*\d{1,2}(?::\d{2}|\.\d{2})?(?:\s?(?:am|pm))?)?\b`),
		regexp.MustCompile(`(?i)\b(?:` + enMonthPattern + `)\s+\d{1,2},?\s+\d{4}(?:\s*(?:at)?\s*\d{1,2}(?::\d{2})?(?:\s?(?:am|pm))?)?\b`),
		regexp.MustCompile(`\b\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?(?:Z|[+-]\d{2}:?\d{2})?\b`),
	}

	weekdayCleaner = regexp.MustCompile(`(?i)\b(?:понедельник|вторник|среда|четверг|пятница|суббота|воскресенье|monday|tuesday|wednesday|thursday|friday|saturday|sunday),?\s*`)
	atCleaner      = regexp.MustCompile(`(?i)(^|\s)(?:в|at)\s+`)
	ampmSpaceRE    = regexp.MustCompile(`(?i)\b(\d{1,2}(?::\d{2})?)\s*(am|pm)\b`)
)

type layoutSpec struct {
	layout  string
	hasYear bool
}

var dateLayouts = []layoutSpec{
	{layout: time.RFC3339, hasYear: true},
	{layout: "2006-01-02 15:04", hasYear: true},
	{layout: "2006-01-02", hasYear: true},
	{layout: "2 Jan 2006 15:04", hasYear: true},
	{layout: "2 Jan 2006 15.04", hasYear: true},
	{layout: "2 January 2006 15:04", hasYear: true},
	{layout: "2 January 2006 15.04", hasYear: true},
	{layout: "2 Jan 2006 3:04pm", hasYear: true},
	{layout: "2 January 2006 3:04pm", hasYear: true},
	{layout: "02.01.2006 15:04", hasYear: true},
	{layout: "2.1.2006 15:04", hasYear: true},
	{layout: "02-01-2006 15:04", hasYear: true},
	{layout: "2-1-2006 15:04", hasYear: true},
	{layout: "2 Jan 2006", hasYear: true},
	{layout: "2 January 2006", hasYear: true},
	{layout: "02.01.2006", hasYear: true},
	{layout: "2.1.2006", hasYear: true},
	{layout: "January 2, 2006 15:04", hasYear: true},
	{layout: "January 2, 2006 3:04pm", hasYear: true},
	{layout: "January 2, 2006", hasYear: true},
	{layout: "Jan 2, 2006 15:04", hasYear: true},
	{layout: "Jan 2, 2006 3:04pm", hasYear: true},
	{layout: "Jan 2, 2006", hasYear: true},
	{layout: "January 2 2006 15:04", hasYear: true},
	{layout: "January 2 2006", hasYear: true},
	{layout: "2 Jan 06 15:04", hasYear: true},
	{layout: "02.01.06 15:04", hasYear: true},
	{layout: "2 Jan 15:04", hasYear: false},
	{layout: "2 January 15:04", hasYear: false},
	{layout: "2 Jan 3:04pm", hasYear: false},
	{layout: "2 January 3:04pm", hasYear: false},
	{layout: "02.01 15:04", hasYear: false},
	{layout: "2.1 15:04", hasYear: false},
	{layout: "2 Jan", hasYear: false},
	{layout: "2 January", hasYear: false},
	{layout: "02.01", hasYear: false},
	{layout: "2.1", hasYear: false},
	{layout: "January 2 15:04", hasYear: false},
	{layout: "January 2", hasYear: false},
}

func ExtractDateCandidates(text string) []string {
	normalized := NormalizeText(text)
	if normalized == "" {
		return nil
	}
	seen := map[string]struct{}{}
	out := make([]string, 0)
	for _, re := range dateCandidatePatterns {
		for _, match := range re.FindAllString(normalized, -1) {
			clean := strings.TrimSpace(match)
			if clean == "" {
				continue
			}
			if _, ok := seen[clean]; ok {
				continue
			}
			seen[clean] = struct{}{}
			out = append(out, clean)
		}
	}
	if len(out) == 0 {
		return nil
	}
	return out
}

func ParseDateTime(text string) (*time.Time, error) {
	candidates := ExtractDateCandidates(text)
	if len(candidates) == 0 {
		return nil, fmt.Errorf("date not found")
	}
	for _, candidate := range candidates {
		if parsed := parseCandidate(candidate); parsed != nil {
			return parsed, nil
		}
	}
	return nil, fmt.Errorf("unable to parse date from %q", strings.Join(candidates, "; "))
}

func parseCandidate(candidate string) *time.Time {
	normalized := normalizeDateInput(candidate)
	if normalized == "" {
		return nil
	}
	now := time.Now().UTC()
	for _, spec := range dateLayouts {
		t, err := time.ParseInLocation(spec.layout, normalized, time.UTC)
		if err != nil {
			continue
		}
		if !spec.hasYear || t.Year() <= 1 {
			t = time.Date(now.Year(), t.Month(), t.Day(), t.Hour(), t.Minute(), t.Second(), 0, time.UTC)
		}
		return &t
	}
	return nil
}

func normalizeDateInput(candidate string) string {
	s := strings.TrimSpace(candidate)
	s = strings.ReplaceAll(s, "\u00a0", " ")
	s = strings.ToLower(s)
	s = weekdayCleaner.ReplaceAllString(s, "")
	s = replaceRussianMonths(s)
	s = ampmSpaceRE.ReplaceAllString(s, "$1$2")
	s = atCleaner.ReplaceAllString(s, "$1")
	s = strings.Join(strings.Fields(s), " ")
	return strings.TrimSpace(s)
}

func replaceRussianMonths(s string) string {
	keys := make([]string, 0, len(ruMonthToEN))
	for k := range ruMonthToEN {
		keys = append(keys, k)
	}
	// Replace longer forms first to avoid partial overlaps.
	sort.Slice(keys, func(i, j int) bool { return len(keys[i]) > len(keys[j]) })
	for _, ru := range keys {
		s = strings.ReplaceAll(s, ru, ruMonthToEN[ru])
	}
	return s
}
