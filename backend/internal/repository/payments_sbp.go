package repository

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"strings"

	"gigme/backend/internal/models"

	"github.com/jackc/pgx/v5"
)

var (
	ErrSbpQRNotFound = errors.New("sbp qr not found")
)

// UpsertPaymentParams represents upsert payment params.
type UpsertPaymentParams struct {
	OrderID           string
	Provider          string
	ProviderPaymentID string
	Amount            int64
	Status            string
	RawResponseJSON   []byte
}

// UpsertSbpQR handles upsert sbp q r.
func (r *Repository) UpsertSbpQR(ctx context.Context, orderID, qrcID, payload, merchantID, accountID, status string) (models.SbpQR, error) {
	row := r.pool.QueryRow(ctx, `
INSERT INTO sbp_qr (order_id, qrc_id, payload, merchant_id, account_id, status)
VALUES ($1::uuid, $2, $3, $4, $5, $6)
ON CONFLICT (order_id)
DO UPDATE SET
	qrc_id = EXCLUDED.qrc_id,
	payload = EXCLUDED.payload,
	merchant_id = EXCLUDED.merchant_id,
	account_id = EXCLUDED.account_id,
	status = EXCLUDED.status,
	updated_at = now()
RETURNING id::text, order_id::text, qrc_id, payload, merchant_id, account_id, status, created_at, updated_at;`,
		strings.TrimSpace(orderID),
		strings.TrimSpace(qrcID),
		strings.TrimSpace(payload),
		strings.TrimSpace(merchantID),
		strings.TrimSpace(accountID),
		strings.TrimSpace(status),
	)
	return scanSbpQR(row)
}

// GetSbpQRByOrderID returns sbp q r by order i d.
func (r *Repository) GetSbpQRByOrderID(ctx context.Context, orderID string) (models.SbpQR, error) {
	row := r.pool.QueryRow(ctx, `
SELECT id::text, order_id::text, qrc_id, payload, merchant_id, account_id, status, created_at, updated_at
FROM sbp_qr
WHERE order_id = $1::uuid;`, strings.TrimSpace(orderID))
	out, err := scanSbpQR(row)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return models.SbpQR{}, ErrSbpQRNotFound
		}
		return models.SbpQR{}, err
	}
	return out, nil
}

// UpdateSbpQRStatus updates sbp q r status.
func (r *Repository) UpdateSbpQRStatus(ctx context.Context, orderID, status string) error {
	cmd, err := r.pool.Exec(ctx, `
UPDATE sbp_qr
SET status = $2,
	updated_at = now()
WHERE order_id = $1::uuid;`, strings.TrimSpace(orderID), strings.TrimSpace(status))
	if err != nil {
		return err
	}
	if cmd.RowsAffected() == 0 {
		return ErrSbpQRNotFound
	}
	return nil
}

// UpsertPayment handles upsert payment.
func (r *Repository) UpsertPayment(ctx context.Context, params UpsertPaymentParams) (models.Payment, error) {
	provider := strings.TrimSpace(params.Provider)
	if provider == "" {
		provider = "unknown"
	}
	status := strings.TrimSpace(params.Status)
	if status == "" {
		status = "unknown"
	}
	raw := params.RawResponseJSON
	if len(raw) == 0 {
		raw = []byte("{}")
	}

	row := r.pool.QueryRow(ctx, `
INSERT INTO payments (order_id, provider, provider_payment_id, amount, status, raw_response_json)
VALUES ($1::uuid, $2, NULLIF($3, ''), $4, $5, $6::jsonb)
ON CONFLICT (order_id, provider)
DO UPDATE SET
	provider_payment_id = COALESCE(NULLIF(EXCLUDED.provider_payment_id, ''), payments.provider_payment_id),
	amount = EXCLUDED.amount,
	status = EXCLUDED.status,
	raw_response_json = EXCLUDED.raw_response_json,
	updated_at = now()
RETURNING id::text, order_id::text, provider, provider_payment_id, amount, status, raw_response_json, created_at, updated_at;`,
		strings.TrimSpace(params.OrderID),
		provider,
		strings.TrimSpace(params.ProviderPaymentID),
		params.Amount,
		status,
		raw,
	)
	return scanPayment(row)
}

// scanSbpQR scans sbp q r.
func scanSbpQR(row pgx.Row) (models.SbpQR, error) {
	var out models.SbpQR
	if err := row.Scan(
		&out.ID,
		&out.OrderID,
		&out.QRCID,
		&out.Payload,
		&out.MerchantID,
		&out.AccountID,
		&out.Status,
		&out.CreatedAt,
		&out.UpdatedAt,
	); err != nil {
		return out, err
	}
	return out, nil
}

// scanPayment scans payment.
func scanPayment(row pgx.Row) (models.Payment, error) {
	var out models.Payment
	var providerPaymentID sql.NullString
	var raw []byte
	if err := row.Scan(
		&out.ID,
		&out.OrderID,
		&out.Provider,
		&providerPaymentID,
		&out.Amount,
		&out.Status,
		&raw,
		&out.CreatedAt,
		&out.UpdatedAt,
	); err != nil {
		return out, err
	}
	if providerPaymentID.Valid {
		out.ProviderPaymentID = providerPaymentID.String
	}
	if len(raw) > 0 {
		if err := json.Unmarshal(raw, &out.RawResponseJSON); err != nil {
			out.RawResponseJSON = decodeJSONMap(raw)
		}
	}
	return out, nil
}
