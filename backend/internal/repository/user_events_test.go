package repository

import (
	"context"
	"os"
	"testing"
	"time"

	"gigme/backend/internal/db"

	"github.com/jackc/pgx/v5/pgxpool"
)

// TestListUserEventsFiltersByCreator verifies list user events filters by creator behavior.
func TestListUserEventsFiltersByCreator(t *testing.T) {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		t.Skip("DATABASE_URL not set")
	}

	ctx := context.Background()
	pool, err := db.NewPool(ctx, dsn)
	if err != nil {
		t.Skipf("db connection failed: %v", err)
	}
	defer pool.Close()

	repo := New(pool)

	user1ID, err := insertTestUser(ctx, pool, "alpha")
	if err != nil {
		t.Fatalf("insert user1: %v", err)
	}
	user2ID, err := insertTestUser(ctx, pool, "bravo")
	if err != nil {
		t.Fatalf("insert user2: %v", err)
	}

	event1ID, err := insertTestEvent(ctx, pool, user1ID, "User1 event 1")
	if err != nil {
		t.Fatalf("insert event1: %v", err)
	}
	event2ID, err := insertTestEvent(ctx, pool, user1ID, "User1 event 2")
	if err != nil {
		t.Fatalf("insert event2: %v", err)
	}
	_, err = insertTestEvent(ctx, pool, user2ID, "User2 event")
	if err != nil {
		t.Fatalf("insert event3: %v", err)
	}

	cleanupIDs := []int64{event1ID, event2ID}
	t.Cleanup(func() {
		for _, id := range cleanupIDs {
			_, _ = pool.Exec(ctx, "DELETE FROM events WHERE id = $1", id)
		}
		_, _ = pool.Exec(ctx, "DELETE FROM users WHERE id = $1", user1ID)
		_, _ = pool.Exec(ctx, "DELETE FROM users WHERE id = $1", user2ID)
	})

	items, total, err := repo.ListUserEvents(ctx, user1ID, 50, 0)
	if err != nil {
		t.Fatalf("ListUserEvents error: %v", err)
	}
	if total != 2 {
		t.Fatalf("expected total 2, got %d", total)
	}
	if len(items) != 2 {
		t.Fatalf("expected 2 items, got %d", len(items))
	}
	allowed := map[int64]struct{}{event1ID: {}, event2ID: {}}
	for _, item := range items {
		if _, ok := allowed[item.ID]; !ok {
			t.Fatalf("unexpected event id %d in results", item.ID)
		}
	}
}

// insertTestUser handles insert test user.
func insertTestUser(ctx context.Context, pool *pgxpool.Pool, suffix string) (int64, error) {
	telegramID := time.Now().UnixNano()
	row := pool.QueryRow(ctx, `INSERT INTO users (telegram_id, username, first_name, last_name, photo_url)
VALUES ($1, $2, $3, $4, $5)
RETURNING id;`, telegramID, "test_"+suffix, "Test", "User", nil)
	var id int64
	if err := row.Scan(&id); err != nil {
		return 0, err
	}
	return id, nil
}

// insertTestEvent handles insert test event.
func insertTestEvent(ctx context.Context, pool *pgxpool.Pool, userID int64, title string) (int64, error) {
	row := pool.QueryRow(ctx, `INSERT INTO events (creator_user_id, title, description, starts_at, location)
VALUES ($1, $2, $3, $4, ST_SetSRID(ST_MakePoint(0, 0), 4326)::geography)
RETURNING id;`, userID, title, "Test description", time.Now().Add(24*time.Hour))
	var id int64
	if err := row.Scan(&id); err != nil {
		return 0, err
	}
	return id, nil
}
