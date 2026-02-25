package eventparser

import (
	"context"
	"log/slog"
	"sync"

	"gigme/backend/internal/eventparser/core"
	"gigme/backend/internal/eventparser/fetch"
	"gigme/backend/internal/eventparser/parsers"
)

var (
	defaultOnce       sync.Once
	defaultDispatcher *core.Dispatcher
)

// ParseEvent parses event.
func ParseEvent(ctx context.Context, input string) (*core.EventData, error) {
	return DefaultDispatcher().ParseEvent(ctx, input)
}

// ParseEventWithSource parses event with source.
func ParseEventWithSource(ctx context.Context, input string, source core.SourceType) (*core.EventData, error) {
	return DefaultDispatcher().ParseEventWithSource(ctx, input, source)
}

// ParseEventsWithSource parses events with source.
func ParseEventsWithSource(ctx context.Context, input string, source core.SourceType) ([]*core.EventData, error) {
	return DefaultDispatcher().ParseEventsWithSource(ctx, input, source)
}

// DefaultDispatcher handles default dispatcher.
func DefaultDispatcher() *core.Dispatcher {
	defaultOnce.Do(func() {
		defaultDispatcher = NewDispatcher(nil, nil, nil)
	})
	return defaultDispatcher
}

// NewDispatcher creates dispatcher.
func NewDispatcher(fetcherImpl core.Fetcher, logger *slog.Logger, browser core.BrowserFetcher) *core.Dispatcher {
	if logger == nil {
		logger = slog.Default()
	}
	if fetcherImpl == nil {
		fetcherImpl = fetch.NewHTTPFetcher(logger)
	}
	_ = browser // future extension hook
	return core.NewDispatcher(map[core.SourceType]core.Parser{
		core.SourceTelegram:  parsers.NewTelegramParser(fetcherImpl, logger),
		core.SourceWeb:       parsers.NewWebParser(fetcherImpl, logger),
		core.SourceInstagram: parsers.NewInstagramParser(fetcherImpl, logger),
		core.SourceVK:        parsers.NewVKParser(fetcherImpl, logger),
	})
}
