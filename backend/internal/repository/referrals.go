package repository

import (
	"context"
	"crypto/rand"
	"encoding/base32"
	"errors"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

const (
	referralCodeBytes      = 5
	referralCodeMaxRetries = 5
)

func (r *Repository) GetOrCreateReferralCode(ctx context.Context, userID int64) (string, error) {
	var code string
	if err := r.pool.QueryRow(ctx, `SELECT code FROM referral_codes WHERE owner_user_id = $1`, userID).Scan(&code); err == nil {
		return code, nil
	} else if err != pgx.ErrNoRows {
		return "", err
	}

	for i := 0; i < referralCodeMaxRetries; i++ {
		candidate, err := generateReferralCode()
		if err != nil {
			return "", err
		}
		tag, err := r.pool.Exec(ctx, `
INSERT INTO referral_codes (code, owner_user_id)
VALUES ($1, $2)
ON CONFLICT (owner_user_id) DO NOTHING;`, candidate, userID)
		if err != nil {
			if isUniqueViolation(err) {
				continue
			}
			return "", err
		}
		if tag.RowsAffected() > 0 {
			return candidate, nil
		}
		if err := r.pool.QueryRow(ctx, `SELECT code FROM referral_codes WHERE owner_user_id = $1`, userID).Scan(&code); err == nil {
			return code, nil
		} else if err != pgx.ErrNoRows {
			return "", err
		}
	}

	return "", errors.New("referral code unavailable")
}

func (r *Repository) ClaimReferral(ctx context.Context, inviteeID, eventID int64, refCode string, bonus int64, isNew bool) (bool, int64, int64, error) {
	if !isNew {
		return false, 0, 0, nil
	}
	if inviteeID == 0 || eventID == 0 {
		return false, 0, 0, nil
	}
	refCode = strings.ToUpper(strings.TrimSpace(refCode))
	if refCode == "" {
		return false, 0, 0, nil
	}

	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return false, 0, 0, err
	}
	defer func() {
		_ = tx.Rollback(ctx)
	}()

	var eventExists bool
	if err := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM events WHERE id = $1 AND is_hidden = false)`, eventID).Scan(&eventExists); err != nil {
		return false, 0, 0, err
	}
	if !eventExists {
		return false, 0, 0, nil
	}

	var referralID int64
	var inviterID int64
	if err := tx.QueryRow(ctx, `SELECT id, owner_user_id FROM referral_codes WHERE code = $1`, refCode).Scan(&referralID, &inviterID); err != nil {
		if err == pgx.ErrNoRows {
			return false, 0, 0, nil
		}
		return false, 0, 0, err
	}
	if inviterID == inviteeID {
		return false, 0, 0, nil
	}

	var claimID int64
	if err := tx.QueryRow(ctx, `
INSERT INTO referral_claims (referral_code_id, event_id, invitee_user_id, inviter_user_id, bonus_amount)
VALUES ($1, $2, $3, $4, $5)
ON CONFLICT (invitee_user_id) DO NOTHING
RETURNING id;`, referralID, eventID, inviteeID, inviterID, bonus).Scan(&claimID); err != nil {
		if err == pgx.ErrNoRows {
			return false, 0, 0, nil
		}
		return false, 0, 0, err
	}

	var inviterBalance int64
	if err := tx.QueryRow(ctx, `
UPDATE users
SET balance_tokens = balance_tokens + $2,
	updated_at = now()
WHERE id = $1
RETURNING balance_tokens;`, inviterID, bonus).Scan(&inviterBalance); err != nil {
		return false, 0, 0, err
	}

	var inviteeBalance int64
	if err := tx.QueryRow(ctx, `
UPDATE users
SET balance_tokens = balance_tokens + $2,
	updated_at = now()
WHERE id = $1
RETURNING balance_tokens;`, inviteeID, bonus).Scan(&inviteeBalance); err != nil {
		return false, 0, 0, err
	}

	if err := tx.Commit(ctx); err != nil {
		return false, 0, 0, err
	}
	return true, inviterBalance, inviteeBalance, nil
}

func generateReferralCode() (string, error) {
	buf := make([]byte, referralCodeBytes)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(buf), nil
}

func isUniqueViolation(err error) bool {
	pgErr, ok := err.(*pgconn.PgError)
	return ok && pgErr.Code == "23505"
}
