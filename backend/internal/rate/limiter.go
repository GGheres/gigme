package rate

import (
	"sync"
	"time"
)

type WindowLimiter struct {
	mu              sync.Mutex
	limit           int
	window          time.Duration
	items           map[string]*windowEntry
	lastCleanup     time.Time
	cleanupInterval time.Duration
}

type windowEntry struct {
	start time.Time
	count int
}

func NewWindowLimiter(limit int, window time.Duration) *WindowLimiter {
	return &WindowLimiter{
		limit:           limit,
		window:          window,
		items:           make(map[string]*windowEntry),
		lastCleanup:     time.Now(),
		cleanupInterval: window,
	}
}

func (l *WindowLimiter) Allow(key string) bool {
	now := time.Now()
	l.mu.Lock()
	defer l.mu.Unlock()

	l.maybeCleanup(now)

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

func (l *WindowLimiter) maybeCleanup(now time.Time) {
	if l.cleanupInterval <= 0 || l.window <= 0 {
		return
	}
	if !l.lastCleanup.IsZero() && now.Sub(l.lastCleanup) < l.cleanupInterval {
		return
	}
	for key, entry := range l.items {
		if now.Sub(entry.start) >= l.window {
			delete(l.items, key)
		}
	}
	l.lastCleanup = now
}
