package tests

import (
	"context"
	"fmt"
	"log/slog"
	"sort"

	"gigme/backend/internal/eventparser/core"
	"gigme/backend/internal/eventparser/parsers"
)

type fakeResponse struct {
	body   []byte
	status int
	err    error
}

type fakeFetcher struct {
	responses map[string]fakeResponse
}

func (f *fakeFetcher) Get(_ context.Context, rawURL string, _ map[string]string) ([]byte, int, error) {
	if f == nil {
		return nil, 0, fmt.Errorf("fetcher is nil")
	}
	if resp, ok := f.responses[rawURL]; ok {
		return resp.body, resp.status, resp.err
	}
	keys := make([]string, 0, len(f.responses))
	for k := range f.responses {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return nil, 404, fmt.Errorf("no fake response for %s; available: %v", rawURL, keys)
}

func newTestDispatcher(fetcher core.Fetcher) *core.Dispatcher {
	logger := slog.New(slog.NewTextHandler(ioDiscard{}, nil))
	return core.NewDispatcher(map[core.SourceType]core.Parser{
		core.SourceTelegram:  parsers.NewTelegramParser(fetcher, logger),
		core.SourceWeb:       parsers.NewWebParser(fetcher, logger),
		core.SourceInstagram: parsers.NewInstagramParser(fetcher, logger),
		core.SourceVK:        parsers.NewVKParser(fetcher, logger),
	})
}

type ioDiscard struct{}

func (ioDiscard) Write(p []byte) (int, error) { return len(p), nil }
