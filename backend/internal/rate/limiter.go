package rate

import (
	"sync"
	"time"
)

type WindowLimiter struct {
	mu     sync.Mutex
	limit  int
	window time.Duration
	items  map[string]*windowEntry
}

type windowEntry struct {
	start time.Time
	count int
}

func NewWindowLimiter(limit int, window time.Duration) *WindowLimiter {
	return &WindowLimiter{
		limit:  limit,
		window: window,
		items:  make(map[string]*windowEntry),
	}
}

func (l *WindowLimiter) Allow(key string) bool {
	now := time.Now()
	l.mu.Lock()
	defer l.mu.Unlock()

	entry, ok := l.items[key]
	if !ok {
		l.items[key] = &windowEntry{start: now, count: 1}
		return true
	}

	if now.Sub(entry.start) >= l.window {
		entry.start = now
		entry.count = 1
		return true
	}

	if entry.count >= l.limit {
		return false
	}

	entry.count++
	return true
}
