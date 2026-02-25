package repository

import (
	"context"
	"os"
	"testing"

	"gigme/backend/internal/db"
	"gigme/backend/internal/models"

	"github.com/jackc/pgx/v5/pgxpool"
)

// TestDeleteOrderPaidWithItems verifies delete order paid with items behavior.
func TestDeleteOrderPaidWithItems(t *testing.T) {
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
	userID, err := insertTicketingTestUser(ctx, pool, 778101)
	if err != nil {
		t.Fatalf("insert user: %v", err)
	}
	eventID, err := insertTicketingTestEvent(ctx, pool, userID)
	if err != nil {
		t.Fatalf("insert event: %v", err)
	}
	orderID, productID, err := insertPaidOrderWithTicketItem(ctx, pool, userID, eventID, 1)
	if err != nil {
		t.Fatalf("insert paid order: %v", err)
	}

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM orders WHERE id = $1::uuid`, orderID)
		_, _ = pool.Exec(ctx, `DELETE FROM events WHERE id = $1`, eventID)
		_, _ = pool.Exec(ctx, `DELETE FROM users WHERE id = $1`, userID)
	})

	if err := repo.DeleteOrder(ctx, orderID); err != nil {
		t.Fatalf("DeleteOrder(): %v", err)
	}

	var orderCount int
	if err := pool.QueryRow(ctx, `SELECT count(*) FROM orders WHERE id = $1::uuid`, orderID).Scan(&orderCount); err != nil {
		t.Fatalf("order count: %v", err)
	}
	if orderCount != 0 {
		t.Fatalf("expected order to be deleted, got count=%d", orderCount)
	}

	var soldCount int
	if err := pool.QueryRow(ctx, `SELECT sold_count FROM ticket_products WHERE id = $1::uuid`, productID).Scan(&soldCount); err != nil {
		t.Fatalf("ticket product sold_count: %v", err)
	}
	if soldCount != 0 {
		t.Fatalf("expected sold_count=0, got %d", soldCount)
	}
}

// TestCancelOrderPaidWithItems verifies cancel order paid with items behavior.
func TestCancelOrderPaidWithItems(t *testing.T) {
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
	userID, err := insertTicketingTestUser(ctx, pool, 778102)
	if err != nil {
		t.Fatalf("insert user: %v", err)
	}
	adminID, err := insertTicketingTestUser(ctx, pool, 778103)
	if err != nil {
		t.Fatalf("insert admin: %v", err)
	}
	eventID, err := insertTicketingTestEvent(ctx, pool, userID)
	if err != nil {
		t.Fatalf("insert event: %v", err)
	}
	orderID, productID, err := insertPaidOrderWithTicketItem(ctx, pool, userID, eventID, 1)
	if err != nil {
		t.Fatalf("insert paid order: %v", err)
	}

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM orders WHERE id = $1::uuid`, orderID)
		_, _ = pool.Exec(ctx, `DELETE FROM events WHERE id = $1`, eventID)
		_, _ = pool.Exec(ctx, `DELETE FROM users WHERE id IN ($1, $2)`, userID, adminID)
	})

	detail, err := repo.CancelOrder(ctx, orderID, adminID, "test")
	if err != nil {
		t.Fatalf("CancelOrder(): %v", err)
	}
	if detail.Order.Status != models.OrderStatusCanceled {
		t.Fatalf("expected status=%s, got %s", models.OrderStatusCanceled, detail.Order.Status)
	}

	var soldCount int
	if err := pool.QueryRow(ctx, `SELECT sold_count FROM ticket_products WHERE id = $1::uuid`, productID).Scan(&soldCount); err != nil {
		t.Fatalf("ticket product sold_count: %v", err)
	}
	if soldCount != 0 {
		t.Fatalf("expected sold_count=0, got %d", soldCount)
	}
}

// insertPaidOrderWithTicketItem handles insert paid order with ticket item.
func insertPaidOrderWithTicketItem(ctx context.Context, pool *pgxpool.Pool, userID, eventID int64, quantity int) (string, string, error) {
	var productID string
	if err := pool.QueryRow(ctx, `
INSERT INTO ticket_products (event_id, type, price_cents, sold_count, is_active)
VALUES ($1, $2, 1000, $3, true)
RETURNING id::text;`, eventID, models.TicketTypeSingle, quantity).Scan(&productID); err != nil {
		return "", "", err
	}

	totalCents := int64(1000 * quantity)
	var orderID string
	if err := pool.QueryRow(ctx, `
INSERT INTO orders (user_id, event_id, status, payment_method, subtotal_cents, discount_cents, total_cents, currency)
VALUES ($1, $2, $3, $4, $5, 0, $5, 'USD')
RETURNING id::text;`, userID, eventID, models.OrderStatusPaid, models.PaymentMethodPhone, totalCents).Scan(&orderID); err != nil {
		return "", "", err
	}

	if _, err := pool.Exec(ctx, `
INSERT INTO order_items (order_id, item_type, product_id, product_ref, quantity, unit_price_cents, line_total_cents)
VALUES ($1::uuid, $2, $3::uuid, $4, $5, 1000, $6);`,
		orderID, models.ItemTypeTicket, productID, models.TicketTypeSingle, quantity, totalCents); err != nil {
		return "", "", err
	}

	return orderID, productID, nil
}
