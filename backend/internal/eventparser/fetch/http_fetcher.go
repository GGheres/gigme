package fetch

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"math/rand"
	"net"
	"net/http"
	"net/url"
	"sync"
	"time"
)

const defaultUserAgent = "Mozilla/5.0 (compatible; GigmeEventParser/1.0; +https://gigme.app)"

// HTTPFetcher represents h t t p fetcher.
type HTTPFetcher struct {
	client      *http.Client
	retries     int
	baseBackoff time.Duration
	maxBackoff  time.Duration
	limiter     *HostRateLimiter
	logger      *slog.Logger

	randMu sync.Mutex
	rand   *rand.Rand
}

// HTTPFetcherConfig represents h t t p fetcher config.
type HTTPFetcherConfig struct {
	Timeout      time.Duration
	Retries      int
	BaseBackoff  time.Duration
	MaxBackoff   time.Duration
	RateLimitRPS float64
	RateBurst    int
}

// NewHTTPFetcher creates h t t p fetcher.
func NewHTTPFetcher(logger *slog.Logger) *HTTPFetcher {
	return NewHTTPFetcherWithConfig(logger, HTTPFetcherConfig{})
}

// NewHTTPFetcherWithConfig creates h t t p fetcher with config.
func NewHTTPFetcherWithConfig(logger *slog.Logger, cfg HTTPFetcherConfig) *HTTPFetcher {
	if logger == nil {
		logger = slog.Default()
	}
	if cfg.Timeout <= 0 {
		cfg.Timeout = 12 * time.Second
	}
	if cfg.Retries < 0 {
		cfg.Retries = 2
	}
	if cfg.BaseBackoff <= 0 {
		cfg.BaseBackoff = 250 * time.Millisecond
	}
	if cfg.MaxBackoff <= 0 {
		cfg.MaxBackoff = 3 * time.Second
	}
	if cfg.RateLimitRPS <= 0 {
		cfg.RateLimitRPS = 1.5
	}
	if cfg.RateBurst <= 0 {
		cfg.RateBurst = 2
	}
	transport := &http.Transport{
		Proxy:                 http.ProxyFromEnvironment,
		DialContext:           (&net.Dialer{Timeout: 5 * time.Second, KeepAlive: 30 * time.Second}).DialContext,
		MaxIdleConns:          128,
		MaxIdleConnsPerHost:   8,
		IdleConnTimeout:       60 * time.Second,
		TLSHandshakeTimeout:   5 * time.Second,
		ExpectContinueTimeout: 1 * time.Second,
	}
	return &HTTPFetcher{
		client: &http.Client{
			Timeout:   cfg.Timeout,
			Transport: transport,
		},
		retries:     cfg.Retries,
		baseBackoff: cfg.BaseBackoff,
		maxBackoff:  cfg.MaxBackoff,
		limiter:     NewHostRateLimiter(cfg.RateLimitRPS, cfg.RateBurst),
		logger:      logger,
		rand:        rand.New(rand.NewSource(time.Now().UnixNano())),
	}
}

// Get returns the requested value.
func (f *HTTPFetcher) Get(ctx context.Context, rawURL string, headers map[string]string) ([]byte, int, error) {
	if f == nil {
		return nil, 0, errors.New("fetcher is nil")
	}
	parsedURL, err := url.Parse(rawURL)
	if err != nil {
		return nil, 0, fmt.Errorf("invalid url: %w", err)
	}
	host := parsedURL.Hostname()

	var lastErr error
	for attempt := 0; attempt <= f.retries; attempt++ {
		if err := f.limiter.Wait(ctx, host); err != nil {
			return nil, 0, err
		}
		body, status, err := f.doRequest(ctx, rawURL, headers)
		if err == nil {
			if shouldRetryStatus(status) && attempt < f.retries {
				lastErr = fmt.Errorf("transient status %d", status)
				f.logger.Warn("fetch_retry_status", "host", host, "status", status, "attempt", attempt+1)
				if err := f.sleepBackoff(ctx, attempt); err != nil {
					return nil, status, err
				}
				continue
			}
			return body, status, nil
		}
		lastErr = err
		if !isTransientError(err) || attempt >= f.retries {
			return nil, status, err
		}
		f.logger.Warn("fetch_retry_error", "host", host, "attempt", attempt+1, "error", err)
		if err := f.sleepBackoff(ctx, attempt); err != nil {
			return nil, status, err
		}
	}
	if lastErr == nil {
		lastErr = errors.New("fetch failed")
	}
	return nil, 0, lastErr
}

// doRequest handles do request.
func (f *HTTPFetcher) doRequest(ctx context.Context, rawURL string, headers map[string]string) ([]byte, int, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, rawURL, nil)
	if err != nil {
		return nil, 0, err
	}
	req.Header.Set("User-Agent", defaultUserAgent)
	req.Header.Set("Accept", "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8")
	req.Header.Set("Accept-Language", "en-US,en;q=0.8,ru;q=0.7")
	for k, v := range headers {
		if k == "" || v == "" {
			continue
		}
		req.Header.Set(k, v)
	}

	resp, err := f.client.Do(req)
	if err != nil {
		return nil, 0, err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(io.LimitReader(resp.Body, 5<<20))
	if err != nil {
		return nil, resp.StatusCode, err
	}
	return body, resp.StatusCode, nil
}

// sleepBackoff handles sleep backoff.
func (f *HTTPFetcher) sleepBackoff(ctx context.Context, attempt int) error {
	d := backoffDuration(f.baseBackoff, attempt, f.jitter)
	if d > f.maxBackoff {
		d = f.maxBackoff
	}
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-t.C:
		return nil
	}
}

// jitter handles internal jitter behavior.
func (f *HTTPFetcher) jitter(max int64) int64 {
	if max <= 0 {
		return 0
	}
	f.randMu.Lock()
	defer f.randMu.Unlock()
	return f.rand.Int63n(max + 1)
}

// shouldRetryStatus reports whether should retry status.
func shouldRetryStatus(status int) bool {
	if status == http.StatusTooManyRequests {
		return true
	}
	return status >= 500 && status <= 599
}

// isTransientError reports whether transient error condition is met.
func isTransientError(err error) bool {
	if err == nil {
		return false
	}
	if errors.Is(err, context.DeadlineExceeded) || errors.Is(err, context.Canceled) {
		return true
	}
	var netErr net.Error
	if errors.As(err, &netErr) {
		return netErr.Timeout() || netErr.Temporary()
	}
	return false
}
