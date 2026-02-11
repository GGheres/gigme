package repository

import (
	"context"
	"os"
	"sync"
	"testing"
	"time"

	"gigme/backend/internal/db"
	"gigme/backend/internal/models"
	"gigme/backend/internal/ticketing"

	"github.com/jackc/pgx/v5/pgxpool"
)

func TestRedeemTicketAtomicity(t *testing.T) {
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

	ownerID, err := insertTicketingTestUser(ctx, pool, 777001)
	if err != nil {
		t.Fatalf("insert owner: %v", err)
	}
	adminID, err := insertTicketingTestUser(ctx, pool, 777002)
	if err != nil {
		t.Fatalf("insert admin: %v", err)
	}
	eventID, err := insertTicketingTestEvent(ctx, pool, ownerID)
	if err != nil {
		t.Fatalf("insert event: %v", err)
	}
	orderID, ticketID, payload, secret, err := insertConfirmedOrderWithTicket(ctx, pool, ownerID, eventID)
	if err != nil {
		t.Fatalf("insert order/ticket: %v", err)
	}

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM orders WHERE id = $1::uuid`, orderID)
		_, _ = pool.Exec(ctx, `DELETE FROM events WHERE id = $1`, eventID)
		_, _ = pool.Exec(ctx, `DELETE FROM users WHERE id IN ($1, $2)`, ownerID, adminID)
	})

	var wg sync.WaitGroup
	results := make(chan error, 2)
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, err := repo.RedeemTicket(ctx, ticketID, adminID, payload, secret)
			results <- err
		}()
	}
	wg.Wait()
	close(results)

	success := 0
	alreadyRedeemed := 0
	for err := range results {
		switch {
		case err == nil:
			success++
		case err == ErrTicketAlreadyRedeemed:
			alreadyRedeemed++
		default:
			t.Fatalf("unexpected redeem error: %v", err)
		}
	}
	if success != 1 || alreadyRedeemed != 1 {
		t.Fatalf("expected one success and one already redeemed, got success=%d alreadyRedeemed=%d", success, alreadyRedeemed)
	}
}

func insertTicketingTestUser(ctx context.Context, pool *pgxpool.Pool, telegramID int64) (int64, error) {
	var id int64
	err := pool.QueryRow(ctx, `
INSERT INTO users (telegram_id, username, first_name, last_name)
VALUES ($1, $2, 'Ticket', 'Test')
RETURNING id;`, telegramID, "ticket_test").Scan(&id)
	return id, err
}

func insertTicketingTestEvent(ctx context.Context, pool *pgxpool.Pool, ownerID int64) (int64, error) {
	var id int64
	err := pool.QueryRow(ctx, `
INSERT INTO events (creator_user_id, title, description, starts_at, location)
VALUES ($1, 'Ticketing Test', 'Test event', now() + interval '1 day', ST_SetSRID(ST_MakePoint(55.75, 37.61), 4326)::geography)
RETURNING id;`, ownerID).Scan(&id)
	return id, err
}

func insertConfirmedOrderWithTicket(ctx context.Context, pool *pgxpool.Pool, userID, eventID int64) (string, string, string, string, error) {
	var orderID string
	if err := pool.QueryRow(ctx, `
INSERT INTO orders (user_id, event_id, status, payment_method, subtotal_cents, discount_cents, total_cents, currency)
VALUES ($1, $2, $3, $4, 1000, 0, 1000, 'USD')
RETURNING id::text;`, userID, eventID, models.OrderStatusConfirmed, models.PaymentMethodPhone).Scan(&orderID); err != nil {
		return "", "", "", "", err
	}

	var ticketID string
	if err := pool.QueryRow(ctx, `
INSERT INTO tickets (order_id, user_id, event_id, ticket_type, quantity)
VALUES ($1::uuid, $2, $3, $4, 1)
RETURNING id::text;`, orderID, userID, eventID, models.TicketTypeSingle).Scan(&ticketID); err != nil {
		return "", "", "", "", err
	}

	secret := "test-redeem-secret"
	payload, err := ticketing.SignQRPayload(secret, ticketing.BuildPayload(ticketID, eventID, userID, models.TicketTypeSingle, 1, time.Now().UTC(), "nonce"))
	if err != nil {
		return "", "", "", "", err
	}
	if _, err := pool.Exec(ctx, `
UPDATE tickets
SET qr_payload = $2,
	qr_payload_hash = $3,
	qr_issued_at = now()
WHERE id = $1::uuid;`, ticketID, payload, ticketing.HashPayloadToken(payload)); err != nil {
		return "", "", "", "", err
	}
	return orderID, ticketID, payload, secret, nil
}
