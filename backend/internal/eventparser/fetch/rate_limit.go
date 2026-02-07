package fetch

import (
	"context"
	"sync"
	"time"

	"golang.org/x/time/rate"
)

// HostRateLimiter keeps one token bucket per host.
type HostRateLimiter struct {
	mu       sync.Mutex
	limiters map[string]*rate.Limiter
	rate     rate.Limit
	burst    int
}

func NewHostRateLimiter(rps float64, burst int) *HostRateLimiter {
	if rps <= 0 {
		rps = 1
	}
	if burst <= 0 {
		burst = 1
	}
	return &HostRateLimiter{
		limiters: make(map[string]*rate.Limiter),
		rate:     rate.Limit(rps),
		burst:    burst,
	}
}

func (l *HostRateLimiter) Wait(ctx context.Context, host string) error {
	if l == nil || host == "" {
		return nil
	}
	limiter := l.getLimiter(host)
	return limiter.Wait(ctx)
}

func (l *HostRateLimiter) getLimiter(host string) *rate.Limiter {
	l.mu.Lock()
	defer l.mu.Unlock()
	limiter, ok := l.limiters[host]
	if !ok {
		limiter = rate.NewLimiter(l.rate, l.burst)
		l.limiters[host] = limiter
	}
	return limiter
}

func backoffDuration(base time.Duration, attempt int, jitterFn func(max int64) int64) time.Duration {
	if base <= 0 {
		base = 200 * time.Millisecond
	}
	if attempt < 0 {
		attempt = 0
	}
	backoff := base << attempt
	if jitterFn == nil {
		return backoff
	}
	jitter := time.Duration(jitterFn(int64(base)))
	if jitter < 0 {
		jitter = 0
	}
	return backoff + jitter
}
