package handlers

import (
	"context"
	"testing"
	"time"
)

type testContextKey string

// TestWithDetachedTimeoutKeepsValuesAndIgnoresParentCancellation verifies detached handler contexts survive request cancellation.
func TestWithDetachedTimeoutKeepsValuesAndIgnoresParentCancellation(t *testing.T) {
	t.Parallel()

	parent, parentCancel := context.WithCancel(context.Background())
	t.Cleanup(parentCancel)

	ctxWithValue := context.WithValue(parent, testContextKey('k'), 'v')
	handler := Handler{}

	detachedCtx, detachedCancel := handler.withDetachedTimeout(ctxWithValue, 50*time.Millisecond)
	t.Cleanup(detachedCancel)

	parentCancel()

	select {
	case <-detachedCtx.Done():
		t.Fatal("detached context should ignore parent cancellation")
	default:
	}

	if got := detachedCtx.Value(testContextKey('k')); got != 'v' {
		t.Fatalf("detached context lost request value: got %v", got)
	}

	time.Sleep(80 * time.Millisecond)

	if err := detachedCtx.Err(); err == nil {
		t.Fatal("detached context should still stop on its own deadline")
	}
}
