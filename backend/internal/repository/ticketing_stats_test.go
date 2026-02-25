package repository

import (
	"context"
	"os"
	"testing"

	"gigme/backend/internal/db"
	"gigme/backend/internal/models"
)

// TestGetTicketStatsExcludesCanceledOrdersFromCheckins verifies get ticket stats excludes canceled orders from checkins behavior.
func TestGetTicketStatsExcludesCanceledOrdersFromCheckins(t *testing.T) {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		t.Skip("DATABASE_URL not set")
	}

	ctx := context.Background()
	pool, err := db.NewPool(ctx, dsn)
	if err != nil {
		t.Fatalf("db connection: %v", err)
	}
	defer pool.Close()

	repo := New(pool)

	ownerID, err := insertTicketingTestUser(ctx, pool, 778001)
	if err != nil {
		t.Fatalf("insert owner: %v", err)
	}
	eventID, err := insertTicketingTestEvent(ctx, pool, ownerID)
	if err != nil {
		t.Fatalf("insert event: %v", err)
	}

	var paidOrderID string
	if err := pool.QueryRow(ctx, `
INSERT INTO orders (user_id, event_id, status, payment_method, subtotal_cents, discount_cents, total_cents, currency)
VALUES ($1, $2, $3, $4, 1000, 0, 1000, 'USD')
RETURNING id::text;`, ownerID, eventID, models.OrderStatusPaid, models.PaymentMethodPhone).Scan(&paidOrderID); err != nil {
		t.Fatalf("insert paid order: %v", err)
	}

	if _, err := pool.Exec(ctx, `
INSERT INTO tickets (order_id, user_id, event_id, ticket_type, quantity, redeemed_at)
VALUES ($1::uuid, $2, $3, $4, 1, now());`, paidOrderID, ownerID, eventID, models.TicketTypeSingle); err != nil {
		t.Fatalf("insert paid ticket: %v", err)
	}

	var canceledOrderID string
	if err := pool.QueryRow(ctx, `
INSERT INTO orders (user_id, event_id, status, payment_method, subtotal_cents, discount_cents, total_cents, currency)
VALUES ($1, $2, $3, $4, 1000, 0, 1000, 'USD')
RETURNING id::text;`, ownerID, eventID, models.OrderStatusCanceled, models.PaymentMethodPhone).Scan(&canceledOrderID); err != nil {
		t.Fatalf("insert canceled order: %v", err)
	}

	if _, err := pool.Exec(ctx, `
INSERT INTO tickets (order_id, user_id, event_id, ticket_type, quantity, redeemed_at)
VALUES ($1::uuid, $2, $3, $4, 3, now());`, canceledOrderID, ownerID, eventID, models.TicketTypeSingle); err != nil {
		t.Fatalf("insert canceled ticket: %v", err)
	}

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM orders WHERE id IN ($1::uuid, $2::uuid)`, paidOrderID, canceledOrderID)
		_, _ = pool.Exec(ctx, `DELETE FROM events WHERE id = $1`, eventID)
		_, _ = pool.Exec(ctx, `DELETE FROM users WHERE id = $1`, ownerID)
	})

	stats, err := repo.GetTicketStats(ctx, &eventID)
	if err != nil {
		t.Fatalf("GetTicketStats: %v", err)
	}
	if stats.Global.CheckedInTickets != 1 {
		t.Fatalf("expected checkedInTickets=1, got %d", stats.Global.CheckedInTickets)
	}
	if stats.Global.CheckedInPeople != 1 {
		t.Fatalf("expected checkedInPeople=1, got %d", stats.Global.CheckedInPeople)
	}
}
