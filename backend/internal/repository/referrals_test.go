package repository

import (
	"context"
	"fmt"
	"os"
	"testing"
	"time"

	"gigme/backend/internal/db"

	"github.com/jackc/pgx/v5/pgxpool"
)

// TestClaimReferralAwardsOnce verifies claim referral awards once behavior.
func TestClaimReferralAwardsOnce(t *testing.T) {
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

	inviterID, err := insertTestUser(ctx, pool, "inviter")
	if err != nil {
		t.Fatalf("insert inviter: %v", err)
	}
	inviteeID, err := insertTestUser(ctx, pool, "invitee")
	if err != nil {
		t.Fatalf("insert invitee: %v", err)
	}
	eventID, err := insertTestEvent(ctx, pool, inviterID, "Referral event")
	if err != nil {
		t.Fatalf("insert event: %v", err)
	}
	refCodeID, refCode, err := insertReferralCode(ctx, pool, inviterID)
	if err != nil {
		t.Fatalf("insert referral code: %v", err)
	}

	cleanupReferralData(t, ctx, pool, []int64{refCodeID}, []int64{inviteeID, inviterID}, []int64{eventID})

	awarded, inviterBalance, inviteeBalance, err := repo.ClaimReferral(ctx, inviteeID, eventID, refCode, 100, true)
	if err != nil {
		t.Fatalf("claim referral: %v", err)
	}
	if !awarded {
		t.Fatalf("expected awarded=true")
	}
	if inviterBalance != 100 || inviteeBalance != 100 {
		t.Fatalf("unexpected balances: inviter=%d invitee=%d", inviterBalance, inviteeBalance)
	}

	awarded, inviterBalance, inviteeBalance, err = repo.ClaimReferral(ctx, inviteeID, eventID, refCode, 100, true)
	if err != nil {
		t.Fatalf("repeat claim: %v", err)
	}
	if awarded {
		t.Fatalf("expected awarded=false on repeat")
	}
	if inviterBalance != 0 || inviteeBalance != 0 {
		t.Fatalf("expected zero balances on repeat, got inviter=%d invitee=%d", inviterBalance, inviteeBalance)
	}

	inviterBalance = getUserBalance(t, ctx, pool, inviterID)
	inviteeBalance = getUserBalance(t, ctx, pool, inviteeID)
	if inviterBalance != 100 || inviteeBalance != 100 {
		t.Fatalf("balances changed unexpectedly: inviter=%d invitee=%d", inviterBalance, inviteeBalance)
	}
}

// TestClaimReferralSelfInvite verifies claim referral self invite behavior.
func TestClaimReferralSelfInvite(t *testing.T) {
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

	userID, err := insertTestUser(ctx, pool, "self")
	if err != nil {
		t.Fatalf("insert user: %v", err)
	}
	eventID, err := insertTestEvent(ctx, pool, userID, "Self event")
	if err != nil {
		t.Fatalf("insert event: %v", err)
	}
	refCodeID, refCode, err := insertReferralCode(ctx, pool, userID)
	if err != nil {
		t.Fatalf("insert referral code: %v", err)
	}

	cleanupReferralData(t, ctx, pool, []int64{refCodeID}, []int64{userID}, []int64{eventID})

	awarded, _, _, err := repo.ClaimReferral(ctx, userID, eventID, refCode, 100, true)
	if err != nil {
		t.Fatalf("claim referral: %v", err)
	}
	if awarded {
		t.Fatalf("expected awarded=false for self-invite")
	}
	if balance := getUserBalance(t, ctx, pool, userID); balance != 0 {
		t.Fatalf("expected balance 0, got %d", balance)
	}
}

// TestClaimReferralNotNew verifies claim referral not new behavior.
func TestClaimReferralNotNew(t *testing.T) {
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

	inviterID, err := insertTestUser(ctx, pool, "inviter-old")
	if err != nil {
		t.Fatalf("insert inviter: %v", err)
	}
	inviteeID, err := insertTestUser(ctx, pool, "invitee-old")
	if err != nil {
		t.Fatalf("insert invitee: %v", err)
	}
	eventID, err := insertTestEvent(ctx, pool, inviterID, "Old event")
	if err != nil {
		t.Fatalf("insert event: %v", err)
	}
	refCodeID, refCode, err := insertReferralCode(ctx, pool, inviterID)
	if err != nil {
		t.Fatalf("insert referral code: %v", err)
	}

	cleanupReferralData(t, ctx, pool, []int64{refCodeID}, []int64{inviteeID, inviterID}, []int64{eventID})

	awarded, _, _, err := repo.ClaimReferral(ctx, inviteeID, eventID, refCode, 100, false)
	if err != nil {
		t.Fatalf("claim referral: %v", err)
	}
	if awarded {
		t.Fatalf("expected awarded=false for non-new user")
	}
	if balance := getUserBalance(t, ctx, pool, inviteeID); balance != 0 {
		t.Fatalf("expected invitee balance 0, got %d", balance)
	}
}

// TestClaimReferralMultipleCodes verifies claim referral multiple codes behavior.
func TestClaimReferralMultipleCodes(t *testing.T) {
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

	inviterA, err := insertTestUser(ctx, pool, "inviter-a")
	if err != nil {
		t.Fatalf("insert inviter A: %v", err)
	}
	inviterB, err := insertTestUser(ctx, pool, "inviter-b")
	if err != nil {
		t.Fatalf("insert inviter B: %v", err)
	}
	inviteeID, err := insertTestUser(ctx, pool, "invitee-multi")
	if err != nil {
		t.Fatalf("insert invitee: %v", err)
	}
	eventID, err := insertTestEvent(ctx, pool, inviterA, "Multi event")
	if err != nil {
		t.Fatalf("insert event: %v", err)
	}
	refCodeAID, refCodeA, err := insertReferralCode(ctx, pool, inviterA)
	if err != nil {
		t.Fatalf("insert referral code A: %v", err)
	}
	refCodeBID, refCodeB, err := insertReferralCode(ctx, pool, inviterB)
	if err != nil {
		t.Fatalf("insert referral code B: %v", err)
	}

	cleanupReferralData(t, ctx, pool, []int64{refCodeAID, refCodeBID}, []int64{inviteeID, inviterA, inviterB}, []int64{eventID})

	awarded, _, _, err := repo.ClaimReferral(ctx, inviteeID, eventID, refCodeA, 100, true)
	if err != nil {
		t.Fatalf("claim referral A: %v", err)
	}
	if !awarded {
		t.Fatalf("expected awarded for first claim")
	}

	awarded, _, _, err = repo.ClaimReferral(ctx, inviteeID, eventID, refCodeB, 100, true)
	if err != nil {
		t.Fatalf("claim referral B: %v", err)
	}
	if awarded {
		t.Fatalf("expected awarded=false for second claim")
	}

	if balance := getUserBalance(t, ctx, pool, inviterA); balance != 100 {
		t.Fatalf("expected inviter A balance 100, got %d", balance)
	}
	if balance := getUserBalance(t, ctx, pool, inviterB); balance != 0 {
		t.Fatalf("expected inviter B balance 0, got %d", balance)
	}
	if balance := getUserBalance(t, ctx, pool, inviteeID); balance != 100 {
		t.Fatalf("expected invitee balance 100, got %d", balance)
	}
}

// insertReferralCode handles insert referral code.
func insertReferralCode(ctx context.Context, pool *pgxpool.Pool, ownerID int64) (int64, string, error) {
	code := fmt.Sprintf("TEST%X", time.Now().UnixNano())
	row := pool.QueryRow(ctx, `INSERT INTO referral_codes (code, owner_user_id)
VALUES ($1, $2)
RETURNING id;`, code, ownerID)
	var id int64
	if err := row.Scan(&id); err != nil {
		return 0, "", err
	}
	return id, code, nil
}

// cleanupReferralData handles cleanup referral data.
func cleanupReferralData(t *testing.T, ctx context.Context, pool *pgxpool.Pool, codeIDs []int64, userIDs []int64, eventIDs []int64) {
	t.Helper()
	t.Cleanup(func() {
		if len(codeIDs) > 0 {
			_, _ = pool.Exec(ctx, `DELETE FROM referral_claims WHERE referral_code_id = ANY($1)`, codeIDs)
			_, _ = pool.Exec(ctx, `DELETE FROM referral_codes WHERE id = ANY($1)`, codeIDs)
		}
		if len(eventIDs) > 0 {
			_, _ = pool.Exec(ctx, `DELETE FROM events WHERE id = ANY($1)`, eventIDs)
		}
		if len(userIDs) > 0 {
			_, _ = pool.Exec(ctx, `DELETE FROM users WHERE id = ANY($1)`, userIDs)
		}
	})
}

// getUserBalance returns user balance.
func getUserBalance(t *testing.T, ctx context.Context, pool *pgxpool.Pool, userID int64) int64 {
	t.Helper()
	var balance int64
	if err := pool.QueryRow(ctx, `SELECT balance_tokens FROM users WHERE id = $1`, userID).Scan(&balance); err != nil {
		t.Fatalf("query balance: %v", err)
	}
	return balance
}
