package core

import (
	"context"
	"fmt"
	"time"
)

// EventData is the normalized parser output for all sources.
type EventData struct {
	Name        string     `json:"name"`
	DateTime    *time.Time `json:"date_time,omitempty"`
	Location    string     `json:"location"`
	Description string     `json:"description"`
	Links       []string   `json:"links"`
}

// SourceType represents source type.
type SourceType string

const (
	SourceAuto      SourceType = "auto"
	SourceTelegram  SourceType = "telegram"
	SourceWeb       SourceType = "web"
	SourceInstagram SourceType = "instagram"
	SourceVK        SourceType = "vk"
)

// Valid handles internal valid behavior.
func (s SourceType) Valid() bool {
	switch s {
	case SourceAuto, SourceTelegram, SourceWeb, SourceInstagram, SourceVK:
		return true
	default:
		return false
	}
}

// Parser represents parser.
type Parser interface {
	Parse(ctx context.Context, input string) (*EventData, error)
}

// BatchParser is optional. Parsers may implement it when one input can
// naturally contain multiple events (e.g. Telegram channel stream).
type BatchParser interface {
	ParseMany(ctx context.Context, input string) ([]*EventData, error)
}

// Fetcher represents fetcher.
type Fetcher interface {
	Get(ctx context.Context, url string, headers map[string]string) ([]byte, int, error)
}

// BrowserFetcher is intentionally optional and unused by default.
// It is a future extension point for Playwright/Selenium rendering.
type BrowserFetcher interface {
	Render(ctx context.Context, url string) ([]byte, error)
}

// AuthRequiredError represents auth required error.
type AuthRequiredError struct {
	Source SourceType
	URL    string
	Hint   string
}

// Error handles internal error behavior.
func (e *AuthRequiredError) Error() string {
	if e == nil {
		return "auth required"
	}
	if e.Hint != "" {
		return fmt.Sprintf("auth required for %s (%s): %s", e.Source, e.URL, e.Hint)
	}
	return fmt.Sprintf("auth required for %s (%s)", e.Source, e.URL)
}

// DynamicContentError represents dynamic content error.
type DynamicContentError struct {
	Source SourceType
	URL    string
	Hint   string
}

// Error handles internal error behavior.
func (e *DynamicContentError) Error() string {
	if e == nil {
		return "dynamic content"
	}
	if e.Hint != "" {
		return fmt.Sprintf("dynamic content for %s (%s): %s", e.Source, e.URL, e.Hint)
	}
	return fmt.Sprintf("dynamic content for %s (%s)", e.Source, e.URL)
}

// UnsupportedInputError represents unsupported input error.
type UnsupportedInputError struct {
	Input string
	Hint  string
}

// Error handles internal error behavior.
func (e *UnsupportedInputError) Error() string {
	if e == nil {
		return "unsupported input"
	}
	if e.Hint != "" {
		return fmt.Sprintf("unsupported input %q: %s", e.Input, e.Hint)
	}
	return fmt.Sprintf("unsupported input %q", e.Input)
}
