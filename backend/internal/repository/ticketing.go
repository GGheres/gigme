package repository

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"sort"
	"strings"
	"time"

	"gigme/backend/internal/models"
	"gigme/backend/internal/ticketing"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

var (
	ErrOrderNotFound                = errors.New("order not found")
	ErrOrderStateNotAllowed         = errors.New("order state not allowed")
	ErrInvalidProduct               = errors.New("invalid product selection")
	ErrInvalidTelegramContact       = errors.New("invalid telegram contact")
	ErrPromoInvalid                 = errors.New("promo code is invalid")
	ErrInventoryLimitReached        = errors.New("inventory limit reached")
	ErrTicketAlreadyRedeemed        = errors.New("ticket already redeemed")
	ErrTicketQRMismatch             = errors.New("ticket qr mismatch")
	ErrTicketNotFound               = errors.New("ticket not found")
	ErrTransferProductAlreadyExists = errors.New(
		"transfer product with this direction already exists for selected event",
	)
)

const (
	transferProductScopeField              = "landingKey"
	transferProductDefaultScope            = "space"
	transferProductDirectionConstraintName = "transfer_products_event_id_direction_key"
	transferProductLandingConstraintName   = "transfer_products_event_direction_landing_key_uidx"
)

// queryRunner represents query runner.
type queryRunner interface {
	Query(context.Context, string, ...interface{}) (pgx.Rows, error)
	QueryRow(context.Context, string, ...interface{}) pgx.Row
}

// effectiveTransferInventoryLimit resolves the seat limit for a transfer product.
func effectiveTransferInventoryLimit(inventoryLimit *int) (int, bool) {
	if inventoryLimit != nil {
		return *inventoryLimit, true
	}
	return 0, false
}

// GetPaymentSettings returns payment settings.
func (r *Repository) GetPaymentSettings(ctx context.Context, scope string) (models.PaymentSettings, error) {
	scope = normalizePaymentSettingsScope(scope)
	row := r.pool.QueryRow(ctx, `
SELECT scope, phone_number, usdt_wallet, usdt_network, usdt_memo,
	payment_qr_data,
	phone_enabled, usdt_enabled, payment_qr_enabled, sbp_enabled,
	phone_description, usdt_description, qr_description, sbp_description,
	updated_by, created_at, updated_at
FROM payment_settings_scoped
WHERE scope = $1;`, scope)

	return scanPaymentSettingsRow(row)
}

// UpsertPaymentSettings handles upsert payment settings.
func (r *Repository) UpsertPaymentSettings(ctx context.Context, in models.PaymentSettings) (models.PaymentSettings, error) {
	scope := normalizePaymentSettingsScope(in.Scope)
	row := r.pool.QueryRow(ctx, `
INSERT INTO payment_settings_scoped (
	scope, phone_number, usdt_wallet, usdt_network, usdt_memo,
	payment_qr_data,
	phone_enabled, usdt_enabled, payment_qr_enabled, sbp_enabled,
	phone_description, usdt_description, qr_description, sbp_description, updated_by
) VALUES (
	$1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15
)
ON CONFLICT (scope) DO UPDATE SET
	phone_number = EXCLUDED.phone_number,
	usdt_wallet = EXCLUDED.usdt_wallet,
	usdt_network = EXCLUDED.usdt_network,
	usdt_memo = EXCLUDED.usdt_memo,
	payment_qr_data = EXCLUDED.payment_qr_data,
	phone_enabled = EXCLUDED.phone_enabled,
	usdt_enabled = EXCLUDED.usdt_enabled,
	payment_qr_enabled = EXCLUDED.payment_qr_enabled,
	sbp_enabled = EXCLUDED.sbp_enabled,
	phone_description = EXCLUDED.phone_description,
	usdt_description = EXCLUDED.usdt_description,
	qr_description = EXCLUDED.qr_description,
	sbp_description = EXCLUDED.sbp_description,
	updated_by = EXCLUDED.updated_by,
	updated_at = now()
RETURNING scope, phone_number, usdt_wallet, usdt_network, usdt_memo,
	payment_qr_data,
	phone_enabled, usdt_enabled, payment_qr_enabled, sbp_enabled,
	phone_description, usdt_description, qr_description, sbp_description,
	updated_by, created_at, updated_at;`,
		scope,
		strings.TrimSpace(in.PhoneNumber),
		strings.TrimSpace(in.USDTWallet),
		strings.TrimSpace(in.USDTNetwork),
		strings.TrimSpace(in.USDTMemo),
		strings.TrimSpace(in.PaymentQRData),
		in.PhoneEnabled,
		in.USDTEnabled,
		in.PaymentQREnabled,
		in.SBPEnabled,
		strings.TrimSpace(in.PhoneDescription),
		strings.TrimSpace(in.USDTDescription),
		strings.TrimSpace(in.QRDescription),
		strings.TrimSpace(in.SBPDescription),
		nullInt64Ptr(in.UpdatedBy),
	)

	return scanPaymentSettingsRow(row)
}

// ListTicketProducts lists ticket products.
func (r *Repository) ListTicketProducts(ctx context.Context, eventID *int64, active *bool) ([]models.TicketProduct, error) {
	rows, err := r.pool.Query(ctx, `
SELECT id::text, event_id, name, type, price_cents, inventory_limit, sold_count, is_active, created_by, created_at, updated_at
FROM ticket_products
WHERE ($1::bigint IS NULL OR event_id = $1)
	AND ($2::boolean IS NULL OR is_active = $2)
ORDER BY created_at DESC;`, nullInt64Ptr(eventID), boolPtrOrNil(active))
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	items := make([]models.TicketProduct, 0)
	for rows.Next() {
		product, err := scanTicketProduct(rows)
		if err != nil {
			return nil, err
		}
		items = append(items, product)
	}
	return items, rows.Err()
}

// CreateTicketProduct creates ticket product.
func (r *Repository) CreateTicketProduct(ctx context.Context, createdBy int64, in models.TicketProductInput) (models.TicketProduct, error) {
	row := r.pool.QueryRow(ctx, `
INSERT INTO ticket_products (event_id, name, type, price_cents, inventory_limit, is_active, created_by)
VALUES ($1, $2, $3, $4, $5, $6, $7)
RETURNING id::text, event_id, name, type, price_cents, inventory_limit, sold_count, is_active, created_by, created_at, updated_at;`,
		in.EventID,
		strings.TrimSpace(in.Name),
		strings.ToUpper(strings.TrimSpace(in.Type)),
		in.PriceCents,
		nullIntPtr(in.InventoryLimit),
		in.IsActive,
		nullInt64Ptr(&createdBy),
	)
	return scanTicketProduct(row)
}

// UpdateTicketProduct updates ticket product.
func (r *Repository) UpdateTicketProduct(ctx context.Context, id string, patch models.TicketProductPatch) (models.TicketProduct, error) {
	row := r.pool.QueryRow(ctx, `
UPDATE ticket_products
SET price_cents = COALESCE($2, price_cents),
	inventory_limit = COALESCE($3, inventory_limit),
	is_active = COALESCE($4, is_active),
	updated_at = now()
WHERE id = $1::uuid
RETURNING id::text, event_id, name, type, price_cents, inventory_limit, sold_count, is_active, created_by, created_at, updated_at;`,
		id,
		int64PtrOrNil(patch.PriceCents),
		nullIntPtr(patch.InventoryLimit),
		boolPtrOrNil(patch.IsActive),
	)
	return scanTicketProduct(row)
}

// DeleteTicketProduct deletes ticket product.
func (r *Repository) DeleteTicketProduct(ctx context.Context, id string) error {
	cmd, err := r.pool.Exec(ctx, `DELETE FROM ticket_products WHERE id = $1::uuid`, id)
	if err != nil {
		return err
	}
	if cmd.RowsAffected() == 0 {
		return pgx.ErrNoRows
	}
	return nil
}

// ListTransferProducts lists transfer products.
func (r *Repository) ListTransferProducts(ctx context.Context, eventID *int64, active *bool) ([]models.TransferProduct, error) {
	rows, err := r.pool.Query(ctx, `
SELECT id::text, event_id, name, direction, price_cents, info_json, inventory_limit, sold_count, is_active, created_by, created_at, updated_at
FROM transfer_products
WHERE ($1::bigint IS NULL OR event_id = $1)
	AND ($2::boolean IS NULL OR is_active = $2)
ORDER BY created_at DESC;`, nullInt64Ptr(eventID), boolPtrOrNil(active))
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	items := make([]models.TransferProduct, 0)
	for rows.Next() {
		product, err := scanTransferProduct(rows)
		if err != nil {
			return nil, err
		}
		items = append(items, product)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return filterCurrentTransferProducts(items), nil
}

// CreateTransferProduct creates transfer product.
func (r *Repository) CreateTransferProduct(ctx context.Context, createdBy int64, in models.TransferProductInput) (models.TransferProduct, error) {
	infoJSON, _ := json.Marshal(normalizeTransferProductInfo(in.Info))
	row := r.pool.QueryRow(ctx, `
INSERT INTO transfer_products (event_id, name, direction, price_cents, info_json, inventory_limit, is_active, created_by)
VALUES ($1, $2, $3, $4, $5::jsonb, $6, $7, $8)
RETURNING id::text, event_id, name, direction, price_cents, info_json, inventory_limit, sold_count, is_active, created_by, created_at, updated_at;`,
		in.EventID,
		strings.TrimSpace(in.Name),
		strings.ToUpper(strings.TrimSpace(in.Direction)),
		in.PriceCents,
		infoJSON,
		nullIntPtr(in.InventoryLimit),
		in.IsActive,
		nullInt64Ptr(&createdBy),
	)
	item, err := scanTransferProduct(row)
	if isTransferProductUniqueViolation(err) {
		return models.TransferProduct{}, ErrTransferProductAlreadyExists
	}
	return item, err
}

// UpdateTransferProduct updates transfer product.
func (r *Repository) UpdateTransferProduct(ctx context.Context, id string, patch models.TransferProductPatch) (models.TransferProduct, error) {
	var infoRaw interface{}
	if patch.Info != nil {
		buf, _ := json.Marshal(normalizeTransferProductInfo(patch.Info))
		infoRaw = buf
	}
	var name interface{}
	if patch.Name != nil {
		name = strings.TrimSpace(*patch.Name)
	}

	row := r.pool.QueryRow(ctx, `
UPDATE transfer_products
SET name = COALESCE($2, name),
	price_cents = COALESCE($3, price_cents),
	info_json = COALESCE($4::jsonb, info_json),
	inventory_limit = COALESCE($5, inventory_limit),
	is_active = COALESCE($6, is_active),
	updated_at = now()
WHERE id = $1::uuid
RETURNING id::text, event_id, name, direction, price_cents, info_json, inventory_limit, sold_count, is_active, created_by, created_at, updated_at;`,
		id,
		name,
		int64PtrOrNil(patch.PriceCents),
		infoRaw,
		nullIntPtr(patch.InventoryLimit),
		boolPtrOrNil(patch.IsActive),
	)
	item, err := scanTransferProduct(row)
	if isTransferProductUniqueViolation(err) {
		return models.TransferProduct{}, ErrTransferProductAlreadyExists
	}
	return item, err
}

// DeleteTransferProduct deletes transfer product.
func (r *Repository) DeleteTransferProduct(ctx context.Context, id string) error {
	cmd, err := r.pool.Exec(ctx, `DELETE FROM transfer_products WHERE id = $1::uuid`, id)
	if err != nil {
		return err
	}
	if cmd.RowsAffected() == 0 {
		return pgx.ErrNoRows
	}
	return nil
}

// ListPromoCodes lists promo codes.
func (r *Repository) ListPromoCodes(ctx context.Context, eventID *int64, active *bool) ([]models.PromoCode, error) {
	rows, err := r.pool.Query(ctx, `
SELECT id::text, code, discount_type, value, usage_limit, used_count, active_from, active_to, event_id, is_active, created_by, created_at, updated_at
FROM promo_codes
WHERE ($1::bigint IS NULL OR event_id = $1 OR event_id IS NULL)
	AND ($2::boolean IS NULL OR is_active = $2)
ORDER BY created_at DESC;`, nullInt64Ptr(eventID), boolPtrOrNil(active))
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	items := make([]models.PromoCode, 0)
	for rows.Next() {
		item, err := scanPromoCode(rows)
		if err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

// CreatePromoCode creates promo code.
func (r *Repository) CreatePromoCode(ctx context.Context, createdBy int64, in models.PromoCodeInput) (models.PromoCode, error) {
	row := r.pool.QueryRow(ctx, `
INSERT INTO promo_codes (code, discount_type, value, usage_limit, active_from, active_to, event_id, is_active, created_by)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
RETURNING id::text, code, discount_type, value, usage_limit, used_count, active_from, active_to, event_id, is_active, created_by, created_at, updated_at;`,
		strings.ToUpper(strings.TrimSpace(in.Code)),
		strings.ToUpper(strings.TrimSpace(in.DiscountType)),
		in.Value,
		nullIntPtr(in.UsageLimit),
		in.ActiveFrom,
		in.ActiveTo,
		nullInt64Ptr(in.EventID),
		in.IsActive,
		nullInt64Ptr(&createdBy),
	)
	return scanPromoCode(row)
}

// UpdatePromoCode updates promo code.
func (r *Repository) UpdatePromoCode(ctx context.Context, id string, patch models.PromoCodePatch) (models.PromoCode, error) {
	var discountType interface{}
	if patch.DiscountType != nil {
		discountType = strings.ToUpper(strings.TrimSpace(*patch.DiscountType))
	}

	row := r.pool.QueryRow(ctx, `
UPDATE promo_codes
SET discount_type = COALESCE($2, discount_type),
	value = COALESCE($3, value),
	usage_limit = COALESCE($4, usage_limit),
	active_from = COALESCE($5, active_from),
	active_to = COALESCE($6, active_to),
	event_id = COALESCE($7, event_id),
	is_active = COALESCE($8, is_active),
	updated_at = now()
WHERE id = $1::uuid
RETURNING id::text, code, discount_type, value, usage_limit, used_count, active_from, active_to, event_id, is_active, created_by, created_at, updated_at;`,
		id,
		discountType,
		int64PtrOrNil(patch.Value),
		nullIntPtr(patch.UsageLimit),
		patch.ActiveFrom,
		patch.ActiveTo,
		nullInt64Ptr(patch.EventID),
		boolPtrOrNil(patch.IsActive),
	)
	return scanPromoCode(row)
}

// DeletePromoCode deletes promo code.
func (r *Repository) DeletePromoCode(ctx context.Context, id string) error {
	cmd, err := r.pool.Exec(ctx, `DELETE FROM promo_codes WHERE id = $1::uuid`, id)
	if err != nil {
		return err
	}
	if cmd.RowsAffected() == 0 {
		return pgx.ErrNoRows
	}
	return nil
}

// ListEventProductsForPurchase lists event products for purchase.
func (r *Repository) ListEventProductsForPurchase(ctx context.Context, eventID int64) ([]models.TicketProduct, []models.TransferProduct, error) {
	eid := eventID
	onlyActive := true
	tickets, err := r.ListTicketProducts(ctx, &eid, &onlyActive)
	if err != nil {
		return nil, nil, err
	}

	var eventExists bool
	if err := r.pool.QueryRow(ctx, `
SELECT EXISTS(SELECT 1 FROM events WHERE id = $1);`, eventID).Scan(&eventExists); err != nil {
		return nil, nil, err
	}
	if !eventExists {
		return nil, nil, ErrInvalidProduct
	}

	transfers, err := r.ListTransferProducts(ctx, &eid, &onlyActive)
	if err != nil {
		return nil, nil, err
	}
	return tickets, transfers, nil
}

// filterCurrentTransferProducts excludes products retained only for historical orders.
func filterCurrentTransferProducts(products []models.TransferProduct) []models.TransferProduct {
	filtered := make([]models.TransferProduct, 0, len(products))
	for _, product := range products {
		if isCurrentTransferProduct(product.Info) {
			filtered = append(filtered, product)
		}
	}
	return filtered
}

// isCurrentTransferProduct reports whether a transfer belongs to the active product catalog.
func isCurrentTransferProduct(info map[string]interface{}) bool {
	if info == nil {
		return true
	}
	raw, ok := info[transferProductScopeField]
	if !ok || raw == nil {
		return true
	}
	return strings.EqualFold(strings.TrimSpace(fmt.Sprint(raw)), transferProductDefaultScope)
}

// normalizeTransferProductInfo prevents API clients from creating legacy product scopes.
func normalizeTransferProductInfo(info map[string]interface{}) map[string]interface{} {
	normalized := make(map[string]interface{}, len(info)+1)
	for key, value := range info {
		normalized[key] = value
	}
	normalized[transferProductScopeField] = transferProductDefaultScope
	return normalized
}

// ValidatePromoCode validates promo code.
func (r *Repository) ValidatePromoCode(ctx context.Context, eventID int64, code string, subtotalCents int64) (models.PromoValidation, error) {
	validation := models.PromoValidation{
		Valid:         false,
		Code:          strings.ToUpper(strings.TrimSpace(code)),
		DiscountCents: 0,
		TotalCents:    subtotalCents,
	}
	if validation.Code == "" || subtotalCents <= 0 {
		validation.Reason = "invalid_input"
		return validation, nil
	}

	row := r.pool.QueryRow(ctx, `
SELECT code, discount_type, value, usage_limit, used_count, active_from, active_to, event_id, is_active
FROM promo_codes
WHERE lower(code) = lower($1)
LIMIT 1;`, validation.Code)

	var discountType string
	var value int64
	var usageLimit sql.NullInt32
	var usedCount int
	var activeFrom sql.NullTime
	var activeTo sql.NullTime
	var scopedEventID sql.NullInt64
	var isActive bool
	var outCode string
	if err := row.Scan(&outCode, &discountType, &value, &usageLimit, &usedCount, &activeFrom, &activeTo, &scopedEventID, &isActive); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			validation.Reason = "not_found"
			return validation, nil
		}
		return validation, err
	}

	rule := ticketing.PromoRule{
		Code:         outCode,
		DiscountType: discountType,
		Value:        value,
		UsageLimit:   nullInt32ToIntPtr(usageLimit),
		UsedCount:    usedCount,
		ActiveFrom:   nullTimeToPtr(activeFrom),
		ActiveTo:     nullTimeToPtr(activeTo),
		EventID:      nullInt64ToPtr(scopedEventID),
		IsActive:     isActive,
	}
	result := ticketing.ValidatePromo(rule, ticketing.PromoValidationInput{
		Now:           time.Now().UTC(),
		EventID:       eventID,
		SubtotalCents: subtotalCents,
	})
	validation.Valid = result.Valid
	validation.Reason = result.Reason
	validation.DiscountType = discountType
	validation.Value = value
	validation.DiscountCents = result.DiscountCents
	validation.TotalCents = result.TotalCents
	return validation, nil
}

// CreateOrder creates order.
func (r *Repository) CreateOrder(ctx context.Context, params models.CreateOrderParams) (models.OrderDetail, error) {
	var out models.OrderDetail
	if params.UserID <= 0 || params.EventID <= 0 {
		return out, ErrInvalidProduct
	}
	params.PaymentMethod = strings.ToUpper(strings.TrimSpace(params.PaymentMethod))
	if !isValidPaymentMethod(params.PaymentMethod) {
		return out, ErrInvalidProduct
	}

	ticketSelections := mergeSelections(params.TicketItems)
	transferSelections := mergeSelections(params.TransferItems)
	if len(ticketSelections) == 0 && len(transferSelections) == 0 {
		return out, ErrInvalidProduct
	}
	if len(ticketSelections) > 0 && len(transferSelections) > 0 {
		return out, ErrInvalidProduct
	}

	err := r.WithTx(ctx, func(tx pgx.Tx) error {
		return r.createOrderTx(ctx, tx, params, ticketSelections, transferSelections, &out)
	})
	if err != nil {
		return models.OrderDetail{}, err
	}
	return out, nil
}

// createOrderTx creates order tx.
func (r *Repository) createOrderTx(
	ctx context.Context,
	tx pgx.Tx,
	params models.CreateOrderParams,
	ticketSelections map[string]int,
	transferSelections map[string]int,
	out *models.OrderDetail,
) error {
	var eventTitle string
	if err := tx.QueryRow(ctx, `
SELECT title
FROM events
WHERE id = $1;`, params.EventID).Scan(&eventTitle); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrInvalidProduct
		}
		return err
	}
	// itemDraft represents item draft.
	type itemDraft struct {
		ItemType       string
		ProductID      string
		ProductRef     string
		Quantity       int
		UnitPriceCents int64
		LineTotalCents int64
		Meta           map[string]interface{}
	}
	// ticketDraft represents ticket draft.
	type ticketDraft struct {
		TicketType string
		Quantity   int
	}
	itemDrafts := make([]itemDraft, 0, len(ticketSelections)+len(transferSelections))
	ticketDrafts := make([]ticketDraft, 0)
	subtotal := int64(0)

	for productID, quantity := range ticketSelections {
		var dbID string
		var eventID int64
		var ticketType string
		var priceCents int64
		var isActive bool
		if err := tx.QueryRow(ctx, `
SELECT id::text, event_id, type, price_cents, is_active
FROM ticket_products
WHERE id = $1::uuid
FOR UPDATE;`, productID).Scan(&dbID, &eventID, &ticketType, &priceCents, &isActive); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return ErrInvalidProduct
			}
			return err
		}
		if eventID != params.EventID || !isActive {
			return ErrInvalidProduct
		}
		groupSize, ok := models.TicketGroupSizeByType[ticketType]
		if !ok {
			return ErrInvalidProduct
		}
		lineTotal := priceCents * int64(quantity)
		subtotal += lineTotal
		itemDrafts = append(itemDrafts, itemDraft{
			ItemType:       models.ItemTypeTicket,
			ProductID:      dbID,
			ProductRef:     ticketType,
			Quantity:       quantity,
			UnitPriceCents: priceCents,
			LineTotalCents: lineTotal,
			Meta: map[string]interface{}{
				"ticketType": ticketType,
				"groupSize":  groupSize,
			},
		})
		for i := 0; i < quantity; i++ {
			ticketDrafts = append(ticketDrafts, ticketDraft{TicketType: ticketType, Quantity: groupSize})
		}
	}

	for productID, quantity := range transferSelections {
		var dbID string
		var eventID int64
		var name string
		var direction string
		var priceCents int64
		var isActive bool
		var inventoryLimit sql.NullInt32
		var soldCount int
		var infoRaw []byte
		if err := tx.QueryRow(ctx, `
SELECT id::text, event_id, COALESCE(name, ''), direction, price_cents, is_active, info_json, inventory_limit, sold_count
FROM transfer_products
WHERE id = $1::uuid
FOR UPDATE;`, productID).Scan(&dbID, &eventID, &name, &direction, &priceCents, &isActive, &infoRaw, &inventoryLimit, &soldCount); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return ErrInvalidProduct
			}
			return err
		}
		if eventID != params.EventID || !isActive {
			return ErrInvalidProduct
		}
		transferTicketType := models.TransferTicketType(direction)
		if transferTicketType == "" {
			return ErrInvalidProduct
		}
		if limit, ok := effectiveTransferInventoryLimit(nullInt32ToIntPtr(inventoryLimit)); ok && soldCount+quantity > limit {
			return ErrInventoryLimitReached
		}
		info := decodeJSONMap(infoRaw)
		if !isCurrentTransferProduct(info) {
			return ErrInvalidProduct
		}
		lineTotal := priceCents * int64(quantity)
		subtotal += lineTotal
		itemDrafts = append(itemDrafts, itemDraft{
			ItemType:       models.ItemTypeTransfer,
			ProductID:      dbID,
			ProductRef:     direction,
			Quantity:       quantity,
			UnitPriceCents: priceCents,
			LineTotalCents: lineTotal,
			Meta: map[string]interface{}{
				"direction": direction,
				"name":      strings.TrimSpace(name),
				"info":      info,
			},
		})
		ticketDrafts = append(ticketDrafts, ticketDraft{TicketType: transferTicketType, Quantity: quantity})
	}

	if subtotal <= 0 {
		return ErrInvalidProduct
	}

	var promoCodeID *string
	discount := int64(0)
	promoCode := strings.ToUpper(strings.TrimSpace(params.PromoCode))
	appliedPromoCode := ""
	if promoCode != "" {
		var promoID string
		var dbCode string
		var discountType string
		var value int64
		var usageLimit sql.NullInt32
		var usedCount int
		var activeFrom sql.NullTime
		var activeTo sql.NullTime
		var scopedEventID sql.NullInt64
		var isActive bool
		if err := tx.QueryRow(ctx, `
SELECT id::text, code, discount_type, value, usage_limit, used_count, active_from, active_to, event_id, is_active
FROM promo_codes
WHERE lower(code) = lower($1)
FOR UPDATE;`, promoCode).Scan(
			&promoID,
			&dbCode,
			&discountType,
			&value,
			&usageLimit,
			&usedCount,
			&activeFrom,
			&activeTo,
			&scopedEventID,
			&isActive,
		); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return ErrPromoInvalid
			}
			return err
		}

		result := ticketing.ValidatePromo(ticketing.PromoRule{
			Code:         dbCode,
			DiscountType: discountType,
			Value:        value,
			UsageLimit:   nullInt32ToIntPtr(usageLimit),
			UsedCount:    usedCount,
			ActiveFrom:   nullTimeToPtr(activeFrom),
			ActiveTo:     nullTimeToPtr(activeTo),
			EventID:      nullInt64ToPtr(scopedEventID),
			IsActive:     isActive,
		}, ticketing.PromoValidationInput{
			Now:           time.Now().UTC(),
			EventID:       params.EventID,
			SubtotalCents: subtotal,
		})
		if !result.Valid {
			return ErrPromoInvalid
		}
		discount = result.DiscountCents
		promoCodeID = &promoID
		appliedPromoCode = strings.TrimSpace(dbCode)

		if _, err := tx.Exec(ctx, `
UPDATE promo_codes
SET used_count = used_count + 1, updated_at = now()
WHERE id = $1::uuid;`, promoID); err != nil {
			return err
		}
	}
	total := subtotal - discount
	if total < 0 {
		total = 0
	}
	currency := "RUB"

	row := tx.QueryRow(ctx, `
INSERT INTO orders (
	user_id,
	event_id,
	contact_telegram,
	contact_name,
	contact_phone,
	status,
	payment_method,
	payment_reference,
	promo_code_id,
	subtotal_cents,
	discount_cents,
	total_cents,
	currency,
	payment_notes
) VALUES (
	$1,
	$2,
	$3,
	$4,
	$5,
	$6,
	$7,
	$8,
	$9,
	$10,
	$11,
	$12,
	$13,
	$14
)
RETURNING id::text, user_id, event_id, ''::text, contact_telegram, contact_name, contact_phone, status, payment_method, payment_reference, payment_notes, promo_code_id::text, subtotal_cents, discount_cents, total_cents, currency, confirmed_at, canceled_at, redeemed_at, confirmed_by, canceled_by, canceled_reason, created_at, updated_at;`,
		params.UserID,
		params.EventID,
		nullString(strings.TrimSpace(params.ContactTelegram)),
		nullString(strings.TrimSpace(params.ContactName)),
		nullString(strings.TrimSpace(params.ContactPhone)),
		models.OrderStatusPending,
		params.PaymentMethod,
		nullString(strings.TrimSpace(params.PaymentReference)),
		uuidPtrOrNil(promoCodeID),
		subtotal,
		discount,
		total,
		currency,
		nullString("waiting_for_manual_confirmation"),
	)
	order, err := scanOrder(row)
	if err != nil {
		return err
	}
	order.EventTitle = eventTitle
	order.PromoCode = appliedPromoCode

	orderItems := make([]models.OrderItem, 0, len(itemDrafts))
	for _, draft := range itemDrafts {
		metaRaw, _ := json.Marshal(safeMap(draft.Meta))
		itemRow := tx.QueryRow(ctx, `
INSERT INTO order_items (
	order_id,
	item_type,
	product_id,
	product_ref,
	quantity,
	unit_price_cents,
	line_total_cents,
	meta_json
) VALUES ($1::uuid, $2, $3::uuid, $4, $5, $6, $7, $8::jsonb)
RETURNING id, order_id::text, item_type, product_id::text, product_ref, quantity, unit_price_cents, line_total_cents, meta_json, created_at;`,
			order.ID,
			draft.ItemType,
			draft.ProductID,
			draft.ProductRef,
			draft.Quantity,
			draft.UnitPriceCents,
			draft.LineTotalCents,
			metaRaw,
		)
		item, err := scanOrderItem(itemRow)
		if err != nil {
			return err
		}
		orderItems = append(orderItems, item)
	}

	tickets := make([]models.Ticket, 0, len(ticketDrafts))
	for _, draft := range ticketDrafts {
		ticketRow := tx.QueryRow(ctx, `
INSERT INTO tickets (order_id, user_id, event_id, ticket_type, quantity)
VALUES ($1::uuid, $2, $3, $4, $5)
RETURNING id::text, order_id::text, user_id, event_id, ticket_type, quantity, qr_payload, qr_payload_hash, qr_issued_at, qr_delivered_at, qr_delivery_error, redeemed_at, redeemed_by, created_at;`,
			order.ID,
			params.UserID,
			params.EventID,
			draft.TicketType,
			draft.Quantity,
		)
		ticket, err := scanTicket(ticketRow)
		if err != nil {
			return err
		}
		tickets = append(tickets, ticket)
	}

	out.Order = order
	out.Items = orderItems
	out.Tickets = tickets
	return nil
}

// ListOrders lists orders.
func (r *Repository) ListOrders(ctx context.Context, eventID *int64, status string, from, to *time.Time, limit, offset int) ([]models.OrderSummary, int, error) {
	status = strings.ToUpper(strings.TrimSpace(status))
	if limit <= 0 {
		limit = 50
	}
	if limit > 200 {
		limit = 200
	}
	if offset < 0 {
		offset = 0
	}

	var total int
	if err := r.pool.QueryRow(ctx, `
SELECT count(*)
FROM orders o
WHERE ($1::bigint IS NULL OR o.event_id = $1)
	AND ($2::text = '' OR o.status = $2)
	AND ($3::timestamptz IS NULL OR o.created_at >= $3)
	AND ($4::timestamptz IS NULL OR o.created_at <= $4);`, nullInt64Ptr(eventID), status, from, to).Scan(&total); err != nil {
		return nil, 0, err
	}

	rows, err := r.pool.Query(ctx, `
SELECT
	o.id::text,
	o.user_id,
	o.event_id,
	e.title,
	o.contact_telegram,
	o.contact_name,
	o.contact_phone,
	o.status,
	o.payment_method,
	o.payment_reference,
	o.payment_notes,
	o.promo_code_id::text,
	o.subtotal_cents,
	o.discount_cents,
	o.total_cents,
	o.currency,
	o.confirmed_at,
	o.canceled_at,
	o.redeemed_at,
	o.confirmed_by,
	o.canceled_by,
	o.canceled_reason,
	o.created_at,
	o.updated_at,
	u.id,
	u.telegram_id,
	u.first_name,
	u.last_name,
	u.username
FROM orders o
JOIN users u ON u.id = o.user_id
JOIN events e ON e.id = o.event_id
WHERE ($1::bigint IS NULL OR o.event_id = $1)
	AND ($2::text = '' OR o.status = $2)
	AND ($3::timestamptz IS NULL OR o.created_at >= $3)
	AND ($4::timestamptz IS NULL OR o.created_at <= $4)
ORDER BY o.created_at DESC
LIMIT $5 OFFSET $6;`, nullInt64Ptr(eventID), status, from, to, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	items := make([]models.OrderSummary, 0)
	for rows.Next() {
		item, err := scanOrderSummary(rows)
		if err != nil {
			return nil, 0, err
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, err
	}
	return items, total, nil
}

// ListTransferOrders lists ordered transfer rows for admins.
func (r *Repository) ListTransferOrders(ctx context.Context, eventID *int64, status string, direction string, limit, offset int) ([]models.TransferOrderSummary, int, error) {
	status = strings.ToUpper(strings.TrimSpace(status))
	direction = strings.ToUpper(strings.TrimSpace(direction))
	if direction != "" && models.TransferTicketType(direction) == "" {
		return nil, 0, ErrInvalidProduct
	}
	if limit <= 0 {
		limit = 50
	}
	if limit > 200 {
		limit = 200
	}
	if offset < 0 {
		offset = 0
	}

	var total int
	if err := r.pool.QueryRow(ctx, `
SELECT count(*)
FROM order_items oi
JOIN orders o ON o.id = oi.order_id
WHERE oi.item_type = $1
	AND ($2::bigint IS NULL OR o.event_id = $2)
	AND ($3::text = '' OR o.status = $3)
	AND ($4::text = '' OR oi.product_ref = $4);`, models.ItemTypeTransfer, nullInt64Ptr(eventID), status, direction).Scan(&total); err != nil {
		return nil, 0, err
	}

	rows, err := r.pool.Query(ctx, `
SELECT
	o.id::text,
	o.status,
	o.created_at,
	o.event_id,
	e.title,
	o.user_id,
	o.contact_telegram,
	o.contact_name,
	o.contact_phone,
	u.id,
	u.telegram_id,
	u.first_name,
	u.last_name,
	u.username,
	oi.id,
	oi.order_id::text,
	oi.item_type,
	oi.product_id::text,
	oi.product_ref,
	oi.quantity,
	oi.unit_price_cents,
	oi.line_total_cents,
	oi.meta_json,
	oi.created_at
FROM order_items oi
JOIN orders o ON o.id = oi.order_id
JOIN events e ON e.id = o.event_id
JOIN users u ON u.id = o.user_id
WHERE oi.item_type = $1
	AND ($2::bigint IS NULL OR o.event_id = $2)
	AND ($3::text = '' OR o.status = $3)
	AND ($4::text = '' OR oi.product_ref = $4)
ORDER BY o.created_at DESC, oi.id DESC
LIMIT $5 OFFSET $6;`, models.ItemTypeTransfer, nullInt64Ptr(eventID), status, direction, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	items := make([]models.TransferOrderSummary, 0)
	for rows.Next() {
		item, err := scanTransferOrderSummary(rows)
		if err != nil {
			return nil, 0, err
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, err
	}
	return items, total, nil
}

// MoveTransferOrderItem moves one ordered transfer row to another transfer product.
func (r *Repository) MoveTransferOrderItem(ctx context.Context, itemID int64, targetProductID string, qrSecret string) (models.TransferOrderSummary, models.OrderDetail, int64, error) {
	var out models.TransferOrderSummary
	var detail models.OrderDetail
	var telegramID int64
	targetProductID = strings.TrimSpace(targetProductID)
	if itemID <= 0 || targetProductID == "" {
		return out, detail, 0, ErrInvalidProduct
	}

	err := r.WithTx(ctx, func(tx pgx.Tx) error {
		// lockedTransferItem contains the current transfer item and its parent order.
		type lockedTransferItem struct {
			orderID          string
			orderStatus      string
			userID           int64
			eventID          int64
			currentProductID string
			currentDirection string
			quantity         int
			currentLineTotal int64
		}

		var current lockedTransferItem
		if err := tx.QueryRow(ctx, `
SELECT
	oi.order_id::text,
	o.status,
	o.user_id,
	o.event_id,
	oi.product_id::text,
	oi.product_ref,
	oi.quantity,
	oi.line_total_cents
FROM order_items oi
JOIN orders o ON o.id = oi.order_id
WHERE oi.id = $1
	AND oi.item_type = $2
FOR UPDATE OF oi, o;`, itemID, models.ItemTypeTransfer).Scan(
			&current.orderID,
			&current.orderStatus,
			&current.userID,
			&current.eventID,
			&current.currentProductID,
			&current.currentDirection,
			&current.quantity,
			&current.currentLineTotal,
		); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return ErrOrderNotFound
			}
			return err
		}

		if isRedeemedOrderStatus(current.orderStatus) {
			return ErrOrderStateNotAllowed
		}

		if current.currentProductID == targetProductID {
			var err error
			out, err = r.fetchTransferOrderSummaryByItemIDTx(ctx, tx, itemID)
			if err != nil {
				return err
			}
			if err := tx.QueryRow(ctx, `SELECT telegram_id FROM users WHERE id = $1`, current.userID).Scan(&telegramID); err != nil && !errors.Is(err, pgx.ErrNoRows) {
				return err
			}
			detail, err = r.fetchOrderDetail(ctx, tx, current.orderID, true)
			return err
		}

		// targetTransferProduct contains the product selected as the new transfer target.
		type targetTransferProduct struct {
			id             string
			eventID        int64
			name           string
			direction      string
			priceCents     int64
			infoRaw        []byte
			inventoryLimit *int
			soldCount      int
		}

		var target targetTransferProduct
		var inventoryLimit sql.NullInt32
		if err := tx.QueryRow(ctx, `
SELECT id::text, event_id, COALESCE(name, ''), direction, price_cents, info_json, inventory_limit, sold_count
FROM transfer_products
WHERE id = $1::uuid
FOR UPDATE;`, targetProductID).Scan(
			&target.id,
			&target.eventID,
			&target.name,
			&target.direction,
			&target.priceCents,
			&target.infoRaw,
			&inventoryLimit,
			&target.soldCount,
		); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return ErrInvalidProduct
			}
			return err
		}
		target.inventoryLimit = nullInt32ToIntPtr(inventoryLimit)

		target.direction = strings.ToUpper(strings.TrimSpace(target.direction))
		if target.eventID != current.eventID || models.TransferTicketType(target.direction) == "" {
			return ErrInvalidProduct
		}

		if isPaidOrderStatus(current.orderStatus) {
			if _, err := tx.Exec(ctx, `
UPDATE transfer_products
SET sold_count = GREATEST(0, sold_count - $2),
	updated_at = now()
WHERE id = $1::uuid;`, current.currentProductID, current.quantity); err != nil {
				return err
			}
			if limit, ok := effectiveTransferInventoryLimit(target.inventoryLimit); ok && target.soldCount+current.quantity > limit {
				return ErrInventoryLimitReached
			}
			if _, err := tx.Exec(ctx, `
UPDATE transfer_products
SET sold_count = sold_count + $2,
	updated_at = now()
WHERE id = $1::uuid;`, target.id, current.quantity); err != nil {
				return err
			}
		}

		lineTotal := target.priceCents * int64(current.quantity)
		metaRaw, err := json.Marshal(map[string]interface{}{
			"direction": target.direction,
			"name":      strings.TrimSpace(target.name),
			"info":      decodeJSONMap(target.infoRaw),
		})
		if err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `
UPDATE order_items
SET product_id = $2::uuid,
	product_ref = $3,
	unit_price_cents = $4,
	line_total_cents = $5,
	meta_json = $6
WHERE id = $1
	AND item_type = $7;`, itemID, target.id, target.direction, target.priceCents, lineTotal, metaRaw, models.ItemTypeTransfer); err != nil {
			return err
		}

		delta := lineTotal - current.currentLineTotal
		if delta != 0 {
			if _, err := tx.Exec(ctx, `
UPDATE orders
SET subtotal_cents = GREATEST(0, subtotal_cents + $2),
	total_cents = GREATEST(0, subtotal_cents + $2 - discount_cents),
	updated_at = now()
WHERE id = $1::uuid;`, current.orderID, delta); err != nil {
				return err
			}
		}

		if err := r.ensureTransferTicketsTx(ctx, tx, current.orderID, current.userID, current.eventID); err != nil {
			return err
		}
		if isPaidOrderStatus(current.orderStatus) {
			if err := r.issueMissingTicketQRCodesTx(ctx, tx, current.orderID, qrSecret); err != nil {
				return err
			}
		}

		out, err = r.fetchTransferOrderSummaryByItemIDTx(ctx, tx, itemID)
		if err != nil {
			return err
		}
		if err := tx.QueryRow(ctx, `SELECT telegram_id FROM users WHERE id = $1`, current.userID).Scan(&telegramID); err != nil && !errors.Is(err, pgx.ErrNoRows) {
			return err
		}
		detail, err = r.fetchOrderDetail(ctx, tx, current.orderID, true)
		return err
	})
	if err != nil {
		return models.TransferOrderSummary{}, models.OrderDetail{}, 0, err
	}
	return out, detail, telegramID, nil
}

// fetchTransferOrderSummaryByItemIDTx returns one admin transfer order row inside a transaction.
func (r *Repository) fetchTransferOrderSummaryByItemIDTx(ctx context.Context, tx pgx.Tx, itemID int64) (models.TransferOrderSummary, error) {
	row := tx.QueryRow(ctx, `
SELECT
	o.id::text,
	o.status,
	o.created_at,
	o.event_id,
	e.title,
	o.user_id,
	o.contact_telegram,
	o.contact_name,
	o.contact_phone,
	u.id,
	u.telegram_id,
	u.first_name,
	u.last_name,
	u.username,
	oi.id,
	oi.order_id::text,
	oi.item_type,
	oi.product_id::text,
	oi.product_ref,
	oi.quantity,
	oi.unit_price_cents,
	oi.line_total_cents,
	oi.meta_json,
	oi.created_at
FROM order_items oi
JOIN orders o ON o.id = oi.order_id
JOIN events e ON e.id = o.event_id
JOIN users u ON u.id = o.user_id
WHERE oi.id = $1
	AND oi.item_type = $2;`, itemID, models.ItemTypeTransfer)
	return scanTransferOrderSummary(row)
}

// ListMyOrders lists my orders.
func (r *Repository) ListMyOrders(ctx context.Context, userID int64, limit, offset int) ([]models.OrderSummary, int, error) {
	if userID <= 0 {
		return nil, 0, nil
	}
	if limit <= 0 {
		limit = 50
	}
	if limit > 200 {
		limit = 200
	}
	if offset < 0 {
		offset = 0
	}

	var total int
	if err := r.pool.QueryRow(ctx, `SELECT count(*) FROM orders WHERE user_id = $1`, userID).Scan(&total); err != nil {
		return nil, 0, err
	}

	rows, err := r.pool.Query(ctx, `
SELECT
	o.id::text,
	o.user_id,
	o.event_id,
	e.title,
	o.contact_telegram,
	o.contact_name,
	o.contact_phone,
	o.status,
	o.payment_method,
	o.payment_reference,
	o.payment_notes,
	o.promo_code_id::text,
	o.subtotal_cents,
	o.discount_cents,
	o.total_cents,
	o.currency,
	o.confirmed_at,
	o.canceled_at,
	o.redeemed_at,
	o.confirmed_by,
	o.canceled_by,
	o.canceled_reason,
	o.created_at,
	o.updated_at,
	u.id,
	u.telegram_id,
	u.first_name,
	u.last_name,
	u.username
FROM orders o
JOIN users u ON u.id = o.user_id
JOIN events e ON e.id = o.event_id
WHERE o.user_id = $1
ORDER BY o.created_at DESC
LIMIT $2 OFFSET $3;`, userID, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	items := make([]models.OrderSummary, 0)
	for rows.Next() {
		item, err := scanOrderSummary(rows)
		if err != nil {
			return nil, 0, err
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, err
	}
	return items, total, nil
}

// GetOrderDetail returns order detail.
func (r *Repository) GetOrderDetail(ctx context.Context, orderID string, includeUser bool) (models.OrderDetail, error) {
	return r.fetchOrderDetail(ctx, r.pool, orderID, includeUser)
}

// fetchOrderDetail handles fetch order detail.
func (r *Repository) fetchOrderDetail(ctx context.Context, q queryRunner, orderID string, includeUser bool) (models.OrderDetail, error) {
	var out models.OrderDetail
	order, err := scanOrder(q.QueryRow(ctx, `
SELECT
	o.id::text,
	o.user_id,
	o.event_id,
	e.title,
	o.contact_telegram,
	o.contact_name,
	o.contact_phone,
	o.status,
	o.payment_method,
	o.payment_reference,
	o.payment_notes,
	o.promo_code_id::text,
	o.subtotal_cents,
	o.discount_cents,
	o.total_cents,
	o.currency,
	o.confirmed_at,
	o.canceled_at,
	o.redeemed_at,
	o.confirmed_by,
	o.canceled_by,
	o.canceled_reason,
	o.created_at,
	o.updated_at
FROM orders o
JOIN events e ON e.id = o.event_id
WHERE o.id = $1::uuid;`, orderID))
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return out, ErrOrderNotFound
		}
		return out, err
	}
	if order.PromoCodeID != nil {
		promoCode, err := r.promoCodeForOrder(ctx, q, *order.PromoCodeID)
		if err != nil {
			return out, err
		}
		order.PromoCode = promoCode
	}
	out.Order = order

	if includeUser {
		var user models.OrderUserSummary
		var firstName sql.NullString
		var lastName sql.NullString
		var username sql.NullString
		if err := q.QueryRow(ctx, `
SELECT id, telegram_id, first_name, last_name, username
FROM users
WHERE id = $1;`, order.UserID).Scan(&user.ID, &user.TelegramID, &firstName, &lastName, &username); err != nil {
			if !errors.Is(err, pgx.ErrNoRows) {
				return out, err
			}
		} else {
			if firstName.Valid {
				user.FirstName = firstName.String
			}
			if lastName.Valid {
				user.LastName = lastName.String
			}
			if username.Valid {
				user.Username = username.String
			}
			out.User = &user
		}
	}

	itemRows, err := q.Query(ctx, `
SELECT id, order_id::text, item_type, product_id::text, product_ref, quantity, unit_price_cents, line_total_cents, meta_json, created_at
FROM order_items
WHERE order_id = $1::uuid
ORDER BY id ASC;`, orderID)
	if err != nil {
		return out, err
	}
	items := make([]models.OrderItem, 0)
	for itemRows.Next() {
		item, err := scanOrderItem(itemRows)
		if err != nil {
			itemRows.Close()
			return out, err
		}
		items = append(items, item)
	}
	if err := itemRows.Err(); err != nil {
		itemRows.Close()
		return out, err
	}
	itemRows.Close()
	out.Items = items

	ticketRows, err := q.Query(ctx, `
SELECT id::text, order_id::text, user_id, event_id, ticket_type, quantity, qr_payload, qr_payload_hash, qr_issued_at, qr_delivered_at, qr_delivery_error, redeemed_at, redeemed_by, created_at
FROM tickets
WHERE order_id = $1::uuid
ORDER BY created_at ASC, id ASC;`, orderID)
	if err != nil {
		return out, err
	}
	tickets := make([]models.Ticket, 0)
	for ticketRows.Next() {
		ticket, err := scanTicket(ticketRows)
		if err != nil {
			ticketRows.Close()
			return out, err
		}
		tickets = append(tickets, ticket)
	}
	if err := ticketRows.Err(); err != nil {
		ticketRows.Close()
		return out, err
	}
	ticketRows.Close()
	out.Tickets = tickets
	return out, nil
}

// ConfirmOrder handles confirm order.
func (r *Repository) ConfirmOrder(ctx context.Context, orderID string, adminID int64, qrSecret string) (models.OrderDetail, int64, bool, error) {
	var detail models.OrderDetail
	var telegramID int64
	confirmedNow := false
	secret := strings.TrimSpace(qrSecret)
	if secret == "" {
		return detail, 0, false, fmt.Errorf("qr secret is required")
	}

	err := r.WithTx(ctx, func(tx pgx.Tx) error {
		var orderStatus string
		var userID int64
		var eventID int64
		if err := tx.QueryRow(ctx, `
SELECT o.status, o.user_id, o.event_id
FROM orders o
WHERE o.id = $1::uuid
			FOR UPDATE OF o;`, orderID).Scan(&orderStatus, &userID, &eventID); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return ErrOrderNotFound
			}
			return err
		}

		if isPendingOrderStatus(orderStatus) {
			// lockedOrderItem represents locked order item.
			type lockedOrderItem struct {
				itemType  string
				productID string
				quantity  int
			}
			itemRows, err := tx.Query(ctx, `
SELECT item_type, product_id::text, quantity
FROM order_items
WHERE order_id = $1::uuid
ORDER BY id ASC
FOR UPDATE;`, orderID)
			if err != nil {
				return err
			}
			lockedItems := make([]lockedOrderItem, 0, 8)
			for itemRows.Next() {
				var item lockedOrderItem
				if err := itemRows.Scan(&item.itemType, &item.productID, &item.quantity); err != nil {
					itemRows.Close()
					return err
				}
				lockedItems = append(lockedItems, item)
			}
			if err := itemRows.Err(); err != nil {
				itemRows.Close()
				return err
			}
			itemRows.Close()

			for _, item := range lockedItems {
				switch item.itemType {
				case models.ItemTypeTicket:
					cmd, err := tx.Exec(ctx, `
UPDATE ticket_products
SET sold_count = sold_count + $2,
	 updated_at = now()
WHERE id = $1::uuid
	AND (inventory_limit IS NULL OR sold_count + $2 <= inventory_limit);`, item.productID, item.quantity)
					if err != nil {
						return err
					}
					if cmd.RowsAffected() == 0 {
						return ErrInventoryLimitReached
					}
				case models.ItemTypeTransfer:
					var inventoryLimit sql.NullInt32
					var soldCount int
					if err := tx.QueryRow(ctx, `
SELECT inventory_limit, sold_count
FROM transfer_products
WHERE id = $1::uuid
FOR UPDATE;`, item.productID).Scan(&inventoryLimit, &soldCount); err != nil {
						if errors.Is(err, pgx.ErrNoRows) {
							return ErrInvalidProduct
						}
						return err
					}
					if limit, ok := effectiveTransferInventoryLimit(nullInt32ToIntPtr(inventoryLimit)); ok && soldCount+item.quantity > limit {
						return ErrInventoryLimitReached
					}
					if _, err := tx.Exec(ctx, `
UPDATE transfer_products
SET sold_count = sold_count + $2,
	 updated_at = now()
WHERE id = $1::uuid;`, item.productID, item.quantity); err != nil {
						return err
					}
				}
			}

			var confirmedBy interface{}
			if adminID > 0 {
				confirmedBy = adminID
			}
			if err := r.updateOrderToPaidCompatible(ctx, tx, orderID, confirmedBy); err != nil {
				return err
			}
			confirmedNow = true
		} else if !(isPaidOrderStatus(orderStatus) || isRedeemedOrderStatus(orderStatus)) {
			return ErrOrderStateNotAllowed
		}

		if err := r.ensureTransferTicketsTx(ctx, tx, orderID, userID, eventID); err != nil {
			return err
		}

		ticketRows, err := tx.Query(ctx, `
SELECT id::text, user_id, event_id, ticket_type, quantity, qr_payload, qr_payload_hash, qr_issued_at
FROM tickets
WHERE order_id = $1::uuid
ORDER BY created_at ASC
FOR UPDATE;`, orderID)
		if err != nil {
			return err
		}

		// ticketToIssue represents ticket to issue.
		type ticketToIssue struct {
			id         string
			userID     int64
			eventID    int64
			ticketType string
			quantity   int
		}
		toIssue := make([]ticketToIssue, 0, 8)
		now := time.Now().UTC()
		for ticketRows.Next() {
			var row ticketToIssue
			var existingPayload sql.NullString
			var existingHash sql.NullString
			var existingIssuedAt sql.NullTime
			if err := ticketRows.Scan(&row.id, &row.userID, &row.eventID, &row.ticketType, &row.quantity, &existingPayload, &existingHash, &existingIssuedAt); err != nil {
				ticketRows.Close()
				return err
			}
			if existingPayload.Valid && existingHash.Valid && existingIssuedAt.Valid {
				continue
			}
			toIssue = append(toIssue, row)
		}
		if err := ticketRows.Err(); err != nil {
			ticketRows.Close()
			return err
		}
		ticketRows.Close()

		for _, row := range toIssue {
			nonce, err := ticketing.NewNonce(16)
			if err != nil {
				return err
			}
			payload := ticketing.BuildPayload(row.id, row.eventID, row.userID, row.ticketType, row.quantity, now, nonce)
			token, err := ticketing.SignQRPayload(secret, payload)
			if err != nil {
				return err
			}
			hash := ticketing.HashPayloadToken(token)
			if _, err := tx.Exec(ctx, `
UPDATE tickets
SET qr_payload = $2,
	qr_payload_hash = $3,
	qr_issued_at = $4
WHERE id = $1::uuid;`, row.id, token, hash, now); err != nil {
				return err
			}
		}

		if err := tx.QueryRow(ctx, `SELECT telegram_id FROM users WHERE id = $1`, userID).Scan(&telegramID); err != nil {
			if !errors.Is(err, pgx.ErrNoRows) {
				return err
			}
			telegramID = 0
		}

		detail, err = r.fetchOrderDetail(ctx, tx, orderID, true)
		return err
	})
	if err != nil {
		return models.OrderDetail{}, 0, false, err
	}
	return detail, telegramID, confirmedNow, nil
}

// issueMissingTicketQRCodesTx signs QR payloads for tickets missing issued QR data.
func (r *Repository) issueMissingTicketQRCodesTx(ctx context.Context, tx pgx.Tx, orderID string, qrSecret string) error {
	secret := strings.TrimSpace(qrSecret)
	if secret == "" {
		return fmt.Errorf("qr secret is required")
	}

	ticketRows, err := tx.Query(ctx, `
SELECT id::text, user_id, event_id, ticket_type, quantity, qr_payload, qr_payload_hash, qr_issued_at
FROM tickets
WHERE order_id = $1::uuid
ORDER BY created_at ASC
FOR UPDATE;`, orderID)
	if err != nil {
		return err
	}

	// ticketToIssue represents ticket rows that need a signed QR payload.
	type ticketToIssue struct {
		id         string
		userID     int64
		eventID    int64
		ticketType string
		quantity   int
	}
	toIssue := make([]ticketToIssue, 0, 8)
	now := time.Now().UTC()
	for ticketRows.Next() {
		var row ticketToIssue
		var existingPayload sql.NullString
		var existingHash sql.NullString
		var existingIssuedAt sql.NullTime
		if err := ticketRows.Scan(&row.id, &row.userID, &row.eventID, &row.ticketType, &row.quantity, &existingPayload, &existingHash, &existingIssuedAt); err != nil {
			ticketRows.Close()
			return err
		}
		if existingPayload.Valid && existingHash.Valid && existingIssuedAt.Valid {
			continue
		}
		toIssue = append(toIssue, row)
	}
	if err := ticketRows.Err(); err != nil {
		ticketRows.Close()
		return err
	}
	ticketRows.Close()

	for _, row := range toIssue {
		nonce, err := ticketing.NewNonce(16)
		if err != nil {
			return err
		}
		payload := ticketing.BuildPayload(row.id, row.eventID, row.userID, row.ticketType, row.quantity, now, nonce)
		token, err := ticketing.SignQRPayload(secret, payload)
		if err != nil {
			return err
		}
		hash := ticketing.HashPayloadToken(token)
		if _, err := tx.Exec(ctx, `
UPDATE tickets
SET qr_payload = $2,
	qr_payload_hash = $3,
	qr_issued_at = $4,
	qr_delivered_at = NULL,
	qr_delivery_error = NULL
WHERE id = $1::uuid;`, row.id, token, hash, now); err != nil {
			return err
		}
	}
	return nil
}

// ensureTransferTicketsTx creates QR-bearing ticket rows for ordered transfers.
func (r *Repository) ensureTransferTicketsTx(ctx context.Context, tx pgx.Tx, orderID string, userID int64, eventID int64) error {
	rows, err := tx.Query(ctx, `
SELECT product_ref, SUM(quantity)::int
FROM order_items
WHERE order_id = $1::uuid
	AND item_type = $2
GROUP BY product_ref
ORDER BY product_ref;`, orderID, models.ItemTypeTransfer)
	if err != nil {
		return err
	}
	defer rows.Close()

	type transferTicketDraft struct {
		ticketType string
		quantity   int
	}
	drafts := make([]transferTicketDraft, 0, 3)
	for rows.Next() {
		var direction string
		var quantity int
		if err := rows.Scan(&direction, &quantity); err != nil {
			return err
		}
		ticketType := models.TransferTicketType(strings.ToUpper(strings.TrimSpace(direction)))
		if ticketType == "" {
			return ErrInvalidProduct
		}
		drafts = append(drafts, transferTicketDraft{ticketType: ticketType, quantity: quantity})
	}
	if err := rows.Err(); err != nil {
		return err
	}

	activeTicketTypes := make(map[string]bool, len(drafts))
	for _, draft := range drafts {
		activeTicketTypes[draft.ticketType] = true
	}
	if err := r.deleteObsoleteTransferTicketsTx(ctx, tx, orderID, activeTicketTypes); err != nil {
		return err
	}

	for _, draft := range drafts {
		var existingID string
		var existingQuantity int
		var existingPayload sql.NullString
		err := tx.QueryRow(ctx, `
SELECT id::text, quantity, qr_payload
FROM tickets
WHERE order_id = $1::uuid
	AND ticket_type = $2
ORDER BY created_at ASC
LIMIT 1
FOR UPDATE;`, orderID, draft.ticketType).Scan(&existingID, &existingQuantity, &existingPayload)
		if err != nil && !errors.Is(err, pgx.ErrNoRows) {
			return err
		}
		if errors.Is(err, pgx.ErrNoRows) {
			if _, err := tx.Exec(ctx, `
INSERT INTO tickets (order_id, user_id, event_id, ticket_type, quantity)
VALUES ($1::uuid, $2, $3, $4, $5);`, orderID, userID, eventID, draft.ticketType, draft.quantity); err != nil {
				return err
			}
			continue
		}
		if existingQuantity != draft.quantity {
			if _, err := tx.Exec(ctx, `
UPDATE tickets
SET quantity = $2,
	qr_payload = NULL,
	qr_payload_hash = NULL,
	qr_issued_at = NULL,
	qr_delivered_at = NULL,
	qr_delivery_error = NULL
WHERE id = $1::uuid;`, existingID, draft.quantity); err != nil {
				return err
			}
			continue
		}
		if !existingPayload.Valid || strings.TrimSpace(existingPayload.String) == "" {
			if _, err := tx.Exec(ctx, `
UPDATE tickets
SET quantity = $2
WHERE id = $1::uuid;`, existingID, draft.quantity); err != nil {
				return err
			}
		}
	}
	return nil
}

// deleteObsoleteTransferTicketsTx removes transfer QR rows no longer represented by order items.
func (r *Repository) deleteObsoleteTransferTicketsTx(ctx context.Context, tx pgx.Tx, orderID string, activeTicketTypes map[string]bool) error {
	rows, err := tx.Query(ctx, `
SELECT id::text, ticket_type, redeemed_at
FROM tickets
WHERE order_id = $1::uuid
	AND ticket_type IN ($2, $3, $4)
FOR UPDATE;`, orderID, models.TicketTypeTransferThere, models.TicketTypeTransferBack, models.TicketTypeTransferRoundTrip)
	if err != nil {
		return err
	}
	defer rows.Close()

	type obsoleteTransferTicket struct {
		id         string
		ticketType string
		redeemedAt sql.NullTime
	}
	obsolete := make([]obsoleteTransferTicket, 0, 3)
	for rows.Next() {
		var ticket obsoleteTransferTicket
		if err := rows.Scan(&ticket.id, &ticket.ticketType, &ticket.redeemedAt); err != nil {
			return err
		}
		if activeTicketTypes[strings.ToUpper(strings.TrimSpace(ticket.ticketType))] {
			continue
		}
		if ticket.redeemedAt.Valid {
			return ErrTicketAlreadyRedeemed
		}
		obsolete = append(obsolete, ticket)
	}
	if err := rows.Err(); err != nil {
		return err
	}
	for _, ticket := range obsolete {
		if _, err := tx.Exec(ctx, `DELETE FROM tickets WHERE id = $1::uuid`, ticket.id); err != nil {
			return err
		}
	}
	return nil
}

// CancelOrder handles cancel order.
func (r *Repository) CancelOrder(ctx context.Context, orderID string, adminID int64, reason string) (models.OrderDetail, error) {
	var detail models.OrderDetail
	reason = strings.TrimSpace(reason)
	err := r.WithTx(ctx, func(tx pgx.Tx) error {
		var status string
		var promoCodeID sql.NullString
		if err := tx.QueryRow(ctx, `
SELECT status, promo_code_id::text
FROM orders
WHERE id = $1::uuid
FOR UPDATE;`, orderID).Scan(&status, &promoCodeID); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return ErrOrderNotFound
			}
			return err
		}
		if status == models.OrderStatusRedeemed || status == models.OrderStatusCanceled {
			return ErrOrderStateNotAllowed
		}

		if isPaidOrderStatus(status) {
			// lockedOrderItem represents locked order item.
			type lockedOrderItem struct {
				itemType string
				product  string
				quantity int
			}
			rows, err := tx.Query(ctx, `
SELECT item_type, product_id::text, quantity
FROM order_items
WHERE order_id = $1::uuid
ORDER BY id ASC
FOR UPDATE;`, orderID)
			if err != nil {
				return err
			}
			lockedItems := make([]lockedOrderItem, 0, 8)
			for rows.Next() {
				var itemType string
				var productID string
				var quantity int
				if err := rows.Scan(&itemType, &productID, &quantity); err != nil {
					rows.Close()
					return err
				}
				lockedItems = append(lockedItems, lockedOrderItem{
					itemType: itemType,
					product:  productID,
					quantity: quantity,
				})
			}
			if err := rows.Err(); err != nil {
				rows.Close()
				return err
			}
			rows.Close()

			for _, item := range lockedItems {
				switch item.itemType {
				case models.ItemTypeTicket:
					if _, err := tx.Exec(ctx, `
UPDATE ticket_products
SET sold_count = GREATEST(0, sold_count - $2),
	updated_at = now()
WHERE id = $1::uuid;`, item.product, item.quantity); err != nil {
						return err
					}
				case models.ItemTypeTransfer:
					if _, err := tx.Exec(ctx, `
UPDATE transfer_products
SET sold_count = GREATEST(0, sold_count - $2),
	updated_at = now()
WHERE id = $1::uuid;`, item.product, item.quantity); err != nil {
						return err
					}
				}
			}
		}

		if promoCodeID.Valid && promoCodeID.String != "" {
			if _, err := tx.Exec(ctx, `
UPDATE promo_codes
SET used_count = GREATEST(0, used_count - 1),
	updated_at = now()
WHERE id = $1::uuid;`, promoCodeID.String); err != nil {
				return err
			}
		}

		cmd, err := tx.Exec(ctx, `
UPDATE orders
SET status = $2,
	canceled_at = now(),
	canceled_by = $3,
	canceled_reason = $4,
	updated_at = now()
WHERE id = $1::uuid;`, orderID, models.OrderStatusCanceled, adminID, nullString(reason))
		if err != nil {
			return err
		}
		if cmd.RowsAffected() == 0 {
			return ErrOrderNotFound
		}

		detail, err = r.fetchOrderDetail(ctx, tx, orderID, true)
		return err
	})
	if err != nil {
		return models.OrderDetail{}, err
	}
	return detail, nil
}

// DeleteOrder deletes order.
func (r *Repository) DeleteOrder(ctx context.Context, orderID string) error {
	return r.WithTx(ctx, func(tx pgx.Tx) error {
		var status string
		var promoCodeID sql.NullString
		if err := tx.QueryRow(ctx, `
SELECT status, promo_code_id::text
FROM orders
WHERE id = $1::uuid
FOR UPDATE;`, orderID).Scan(&status, &promoCodeID); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return ErrOrderNotFound
			}
			return err
		}

		if isPaidOrderStatus(status) || isRedeemedOrderStatus(status) {
			// lockedOrderItem represents locked order item.
			type lockedOrderItem struct {
				itemType string
				product  string
				quantity int
			}
			rows, err := tx.Query(ctx, `
SELECT item_type, product_id::text, quantity
FROM order_items
WHERE order_id = $1::uuid
ORDER BY id ASC
FOR UPDATE;`, orderID)
			if err != nil {
				return err
			}
			lockedItems := make([]lockedOrderItem, 0, 8)

			for rows.Next() {
				var itemType string
				var productID string
				var quantity int
				if err := rows.Scan(&itemType, &productID, &quantity); err != nil {
					rows.Close()
					return err
				}
				lockedItems = append(lockedItems, lockedOrderItem{
					itemType: itemType,
					product:  productID,
					quantity: quantity,
				})
			}
			if err := rows.Err(); err != nil {
				rows.Close()
				return err
			}
			rows.Close()

			for _, item := range lockedItems {
				switch item.itemType {
				case models.ItemTypeTicket:
					if _, err := tx.Exec(ctx, `
UPDATE ticket_products
SET sold_count = GREATEST(0, sold_count - $2),
	updated_at = now()
WHERE id = $1::uuid;`, item.product, item.quantity); err != nil {
						return err
					}
				case models.ItemTypeTransfer:
					if _, err := tx.Exec(ctx, `
UPDATE transfer_products
SET sold_count = GREATEST(0, sold_count - $2),
	updated_at = now()
WHERE id = $1::uuid;`, item.product, item.quantity); err != nil {
						return err
					}
				}
			}
		}

		if promoCodeID.Valid && promoCodeID.String != "" && !strings.EqualFold(strings.TrimSpace(status), models.OrderStatusCanceled) {
			if _, err := tx.Exec(ctx, `
UPDATE promo_codes
SET used_count = GREATEST(0, used_count - 1),
	updated_at = now()
WHERE id = $1::uuid;`, promoCodeID.String); err != nil {
				return err
			}
		}

		cmd, err := tx.Exec(ctx, `DELETE FROM orders WHERE id = $1::uuid;`, orderID)
		if err != nil {
			return err
		}
		if cmd.RowsAffected() == 0 {
			return ErrOrderNotFound
		}

		return nil
	})
}

// RedeemTicket handles redeem ticket.
func (r *Repository) RedeemTicket(ctx context.Context, ticketID string, adminID int64, qrPayload string, qrSecret string) (models.TicketRedeemResult, error) {
	var out models.TicketRedeemResult
	secret := strings.TrimSpace(qrSecret)
	if secret == "" {
		return out, fmt.Errorf("qr secret is required")
	}

	err := r.WithTx(ctx, func(tx pgx.Tx) error {
		var ticket models.Ticket
		var storedHash sql.NullString
		var orderStatus string
		if err := tx.QueryRow(ctx, `
SELECT
	t.id::text,
	t.order_id::text,
	t.user_id,
	t.event_id,
	t.ticket_type,
	t.quantity,
		t.qr_payload,
		t.qr_payload_hash,
		t.qr_issued_at,
		t.redeemed_at,
		t.redeemed_by,
		t.created_at,
	o.status
FROM tickets t
JOIN orders o ON o.id = t.order_id
WHERE t.id = $1::uuid
FOR UPDATE;`, ticketID).Scan(
			&ticket.ID,
			&ticket.OrderID,
			&ticket.UserID,
			&ticket.EventID,
			&ticket.TicketType,
			&ticket.Quantity,
			&ticket.QRPayload,
			&storedHash,
			&ticket.QRIssuedAt,
			&ticket.RedeemedAt,
			&ticket.RedeemedBy,
			&ticket.CreatedAt,
			&orderStatus,
		); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return ErrTicketNotFound
			}
			return err
		}
		if storedHash.Valid {
			ticket.QRPayloadHash = storedHash.String
		}
		if ticket.RedeemedAt != nil {
			return ErrTicketAlreadyRedeemed
		}
		if !isPaidOrderStatus(orderStatus) && !isRedeemedOrderStatus(orderStatus) {
			return ErrOrderStateNotAllowed
		}

		if strings.TrimSpace(qrPayload) != "" {
			claims, err := ticketing.VerifyQRPayload(secret, strings.TrimSpace(qrPayload))
			if err != nil {
				return ErrTicketQRMismatch
			}
			if claims.TicketID != ticket.ID || claims.EventID != ticket.EventID || claims.UserID != ticket.UserID || claims.TicketType != ticket.TicketType || claims.Quantity != ticket.Quantity {
				return ErrTicketQRMismatch
			}
			if ticket.QRPayloadHash != "" {
				hash := ticketing.HashPayloadToken(strings.TrimSpace(qrPayload))
				if hash != ticket.QRPayloadHash {
					return ErrTicketQRMismatch
				}
			}
		}

		now := time.Now().UTC()
		cmd, err := tx.Exec(ctx, `
UPDATE tickets
SET redeemed_at = $2,
	redeemed_by = $3
WHERE id = $1::uuid
	AND redeemed_at IS NULL;`, ticket.ID, now, adminID)
		if err != nil {
			return err
		}
		if cmd.RowsAffected() == 0 {
			return ErrTicketAlreadyRedeemed
		}
		ticket.RedeemedAt = &now
		ticket.RedeemedBy = &adminID

		var pending int
		if err := tx.QueryRow(ctx, `
SELECT count(*)
FROM tickets
WHERE order_id = $1::uuid
	AND redeemed_at IS NULL;`, ticket.OrderID).Scan(&pending); err != nil {
			return err
		}
		if pending == 0 {
			if _, err := tx.Exec(ctx, `
	UPDATE orders
SET status = $2,
	redeemed_at = now(),
	updated_at = now()
WHERE id = $1::uuid
	AND status IN ($3, $4, $5);`, ticket.OrderID, models.OrderStatusRedeemed, models.OrderStatusPaid, "CONFIRMED", models.OrderStatusRedeemed); err != nil {
				return err
			}
			orderStatus = models.OrderStatusRedeemed
		}

		out.Ticket = ticket
		out.OrderStatus = orderStatus
		return nil
	})
	if err != nil {
		return models.TicketRedeemResult{}, err
	}
	return out, nil
}

// ListMyTickets lists my tickets.
func (r *Repository) ListMyTickets(ctx context.Context, userID int64, eventID *int64) ([]models.Ticket, error) {
	rows, err := r.pool.Query(ctx, `
SELECT
	t.id::text,
	t.order_id::text,
	t.user_id,
	t.event_id,
	t.ticket_type,
	t.quantity,
		t.qr_payload,
		t.qr_payload_hash,
		t.qr_issued_at,
		t.qr_delivered_at,
		t.qr_delivery_error,
		t.redeemed_at,
	t.redeemed_by,
	t.created_at,
	o.status
FROM tickets t
JOIN orders o ON o.id = t.order_id
WHERE t.user_id = $1
	AND ($2::bigint IS NULL OR t.event_id = $2)
ORDER BY t.created_at DESC;`, userID, nullInt64Ptr(eventID))
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	items := make([]models.Ticket, 0)
	for rows.Next() {
		ticket, err := scanMyTicketWithOrderStatus(rows)
		if err != nil {
			return nil, err
		}
		items = append(items, ticket)
	}
	return items, rows.Err()
}

// ListOrdersNeedingQRDelivery lists confirmed orders with QR codes to issue or send.
func (r *Repository) ListOrdersNeedingQRDelivery(ctx context.Context, limit int) ([]string, error) {
	if limit <= 0 {
		limit = 100
	}
	if limit > 500 {
		limit = 500
	}
	rows, err := r.pool.Query(ctx, `
SELECT DISTINCT o.id::text
FROM orders o
WHERE o.status IN ($1, $2)
	AND (
		EXISTS (
			SELECT 1
			FROM tickets t
			WHERE t.order_id = o.id
				AND (
					t.qr_payload IS NULL
					OR btrim(t.qr_payload) = ''
					OR t.qr_delivered_at IS NULL
				)
		)
		OR EXISTS (
			SELECT 1
			FROM order_items oi
			WHERE oi.order_id = o.id
				AND oi.item_type = $3
				AND NOT EXISTS (
					SELECT 1
					FROM tickets t
					WHERE t.order_id = oi.order_id
						AND t.ticket_type = CASE oi.product_ref
							WHEN $4 THEN $5
							WHEN $6 THEN $7
							WHEN $8 THEN $9
							ELSE ''
						END
				)
		)
	)
ORDER BY o.id::text
LIMIT $10;`,
		models.OrderStatusPaid,
		"CONFIRMED",
		models.ItemTypeTransfer,
		models.TransferDirectionThere,
		models.TicketTypeTransferThere,
		models.TransferDirectionBack,
		models.TicketTypeTransferBack,
		models.TransferDirectionRoundTrip,
		models.TicketTypeTransferRoundTrip,
		limit,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	orderIDs := make([]string, 0)
	for rows.Next() {
		var orderID string
		if err := rows.Scan(&orderID); err != nil {
			return nil, err
		}
		orderIDs = append(orderIDs, orderID)
	}
	return orderIDs, rows.Err()
}

// MarkTicketQRDelivered marks ticket QR delivery as successful.
func (r *Repository) MarkTicketQRDelivered(ctx context.Context, ticketID string) error {
	_, err := r.pool.Exec(ctx, `
UPDATE tickets
SET qr_delivered_at = now(),
	qr_delivery_error = NULL
WHERE id = $1::uuid;`, ticketID)
	return err
}

// MarkTicketQRDeliveryFailed stores the latest ticket QR delivery error.
func (r *Repository) MarkTicketQRDeliveryFailed(ctx context.Context, ticketID string, deliveryError string) error {
	_, err := r.pool.Exec(ctx, `
UPDATE tickets
SET qr_delivery_error = $2
WHERE id = $1::uuid;`, ticketID, nullString(strings.TrimSpace(deliveryError)))
	return err
}

// scanMyTicketWithOrderStatus scans my ticket with order status.
func scanMyTicketWithOrderStatus(row pgx.Row) (models.Ticket, error) {
	var out models.Ticket
	var qrPayload sql.NullString
	var qrPayloadHash sql.NullString
	var qrIssuedAt sql.NullTime
	var qrDeliveredAt sql.NullTime
	var qrDeliveryError sql.NullString
	var redeemedAt sql.NullTime
	var redeemedBy sql.NullInt64
	var orderStatus sql.NullString
	if err := row.Scan(
		&out.ID,
		&out.OrderID,
		&out.UserID,
		&out.EventID,
		&out.TicketType,
		&out.Quantity,
		&qrPayload,
		&qrPayloadHash,
		&qrIssuedAt,
		&qrDeliveredAt,
		&qrDeliveryError,
		&redeemedAt,
		&redeemedBy,
		&out.CreatedAt,
		&orderStatus,
	); err != nil {
		return out, err
	}
	if qrPayload.Valid {
		out.QRPayload = qrPayload.String
	}
	if qrPayloadHash.Valid {
		out.QRPayloadHash = qrPayloadHash.String
	}
	out.QRIssuedAt = nullTimeToPtr(qrIssuedAt)
	out.QRDeliveredAt = nullTimeToPtr(qrDeliveredAt)
	if qrDeliveryError.Valid {
		out.QRDeliveryError = qrDeliveryError.String
	}
	out.RedeemedAt = nullTimeToPtr(redeemedAt)
	if redeemedBy.Valid {
		value := redeemedBy.Int64
		out.RedeemedBy = &value
	}
	if orderStatus.Valid {
		out.OrderStatus = strings.ToUpper(strings.TrimSpace(orderStatus.String))
	}
	return out, nil
}

// GetTicketStats returns ticket stats.
func (r *Repository) GetTicketStats(ctx context.Context, eventID *int64) (models.TicketStats, error) {
	rows, err := r.pool.Query(ctx, `
SELECT
	o.id::text,
	o.event_id,
	e.title,
	o.status,
	CASE
		WHEN o.subtotal_cents > 0 AND COALESCE(oi.line_total_cents, 0) > 0
			THEN ROUND((o.total_cents::numeric * oi.line_total_cents::numeric) / o.subtotal_cents)::bigint
		ELSE 0
	END AS amount_cents,
	COALESCE(oi.item_type, ''),
	COALESCE(oi.product_ref, ''),
	COALESCE(oi.quantity, 0)
FROM orders o
JOIN events e ON e.id = o.event_id
LEFT JOIN order_items oi ON oi.order_id = o.id
WHERE ($1::bigint IS NULL OR o.event_id = $1)
ORDER BY o.created_at DESC;`, nullInt64Ptr(eventID))
	if err != nil {
		return models.TicketStats{}, err
	}
	defer rows.Close()

	aggRows := make([]ticketing.StatsRow, 0)
	for rows.Next() {
		var row ticketing.StatsRow
		if err := rows.Scan(
			&row.OrderID,
			&row.EventID,
			&row.EventTitle,
			&row.Status,
			&row.AmountCents,
			&row.ItemType,
			&row.ProductRef,
			&row.Quantity,
		); err != nil {
			return models.TicketStats{}, err
		}
		aggRows = append(aggRows, row)
	}
	if err := rows.Err(); err != nil {
		return models.TicketStats{}, err
	}

	globalBucket, perEventBuckets := ticketing.AggregateStats(aggRows)
	result := models.TicketStats{
		Global: models.TicketStatsBreakdown{
			PurchasedAmountCents:         globalBucket.PurchasedAmountCents,
			RedeemedAmountCents:          globalBucket.RedeemedAmountCents,
			TransferPurchasedAmountCents: globalBucket.TransferPurchasedAmountCents,
			TransferRedeemedAmountCents:  globalBucket.TransferRedeemedAmountCents,
			TicketTypeCounts:             globalBucket.TicketTypeCounts,
			TransferDirectionCounts:      globalBucket.TransferDirectionCounts,
		},
		Events: make([]models.TicketStatsBreakdown, 0, len(perEventBuckets)),
	}

	eventIDs := make([]int64, 0, len(perEventBuckets))
	for eventKey := range perEventBuckets {
		eventIDs = append(eventIDs, eventKey)
	}
	sort.Slice(eventIDs, func(i, j int) bool { return eventIDs[i] < eventIDs[j] })
	for _, key := range eventIDs {
		bucket := perEventBuckets[key]
		eventIDVal := bucket.EventID
		result.Events = append(result.Events, models.TicketStatsBreakdown{
			EventID:                      &eventIDVal,
			EventTitle:                   bucket.EventTitle,
			PurchasedAmountCents:         bucket.PurchasedAmountCents,
			RedeemedAmountCents:          bucket.RedeemedAmountCents,
			TransferPurchasedAmountCents: bucket.TransferPurchasedAmountCents,
			TransferRedeemedAmountCents:  bucket.TransferRedeemedAmountCents,
			TicketTypeCounts:             bucket.TicketTypeCounts,
			TransferDirectionCounts:      bucket.TransferDirectionCounts,
		})
	}

	eventIndex := make(map[int64]int, len(result.Events))
	for i, item := range result.Events {
		if item.EventID != nil {
			eventIndex[*item.EventID] = i
		}
	}

	checkInRows, err := r.pool.Query(ctx, `
SELECT
	t.event_id,
	COALESCE(e.title, ''),
	count(*) FILTER (
		WHERE t.redeemed_at IS NOT NULL
			AND t.ticket_type NOT LIKE 'TRANSFER_%'
	) AS checked_in_tickets,
	COALESCE(sum(t.quantity) FILTER (
		WHERE t.redeemed_at IS NOT NULL
			AND t.ticket_type NOT LIKE 'TRANSFER_%'
	), 0) AS checked_in_people,
	count(*) FILTER (
		WHERE t.redeemed_at IS NOT NULL
			AND t.ticket_type LIKE 'TRANSFER_%'
	) AS transfer_checked_in_tickets,
	COALESCE(sum(t.quantity) FILTER (
		WHERE t.redeemed_at IS NOT NULL
			AND t.ticket_type LIKE 'TRANSFER_%'
	), 0) AS transfer_checked_in_people
FROM tickets t
JOIN orders o ON o.id = t.order_id
LEFT JOIN events e ON e.id = t.event_id
WHERE ($1::bigint IS NULL OR t.event_id = $1)
  AND UPPER(TRIM(o.status)) IN ('PAID', 'CONFIRMED', 'REDEEMED')
GROUP BY t.event_id, e.title
ORDER BY t.event_id ASC;`, nullInt64Ptr(eventID))
	if err != nil {
		return models.TicketStats{}, err
	}
	defer checkInRows.Close()

	for checkInRows.Next() {
		var eid int64
		var title string
		var checkedInTickets int64
		var checkedInPeople int64
		var transferCheckedInTickets int64
		var transferCheckedInPeople int64
		if err := checkInRows.Scan(
			&eid,
			&title,
			&checkedInTickets,
			&checkedInPeople,
			&transferCheckedInTickets,
			&transferCheckedInPeople,
		); err != nil {
			return models.TicketStats{}, err
		}

		result.Global.CheckedInTickets += checkedInTickets
		result.Global.CheckedInPeople += checkedInPeople
		result.Global.TransferCheckedInTickets += transferCheckedInTickets
		result.Global.TransferCheckedInPeople += transferCheckedInPeople

		if idx, ok := eventIndex[eid]; ok {
			result.Events[idx].CheckedInTickets = checkedInTickets
			result.Events[idx].CheckedInPeople = checkedInPeople
			result.Events[idx].TransferCheckedInTickets = transferCheckedInTickets
			result.Events[idx].TransferCheckedInPeople = transferCheckedInPeople
			if result.Events[idx].EventTitle == "" {
				result.Events[idx].EventTitle = title
			}
			continue
		}

		eventIDVal := eid
		result.Events = append(result.Events, models.TicketStatsBreakdown{
			EventID:                  &eventIDVal,
			EventTitle:               title,
			CheckedInTickets:         checkedInTickets,
			CheckedInPeople:          checkedInPeople,
			TransferCheckedInTickets: transferCheckedInTickets,
			TransferCheckedInPeople:  transferCheckedInPeople,
			TicketTypeCounts: map[string]int64{
				models.TicketTypeSingle:  0,
				models.TicketTypeGroup2:  0,
				models.TicketTypeGroup10: 0,
			},
			TransferDirectionCounts: map[string]int64{
				models.TransferDirectionThere:     0,
				models.TransferDirectionBack:      0,
				models.TransferDirectionRoundTrip: 0,
			},
		})
	}
	if err := checkInRows.Err(); err != nil {
		return models.TicketStats{}, err
	}

	sort.Slice(result.Events, func(i, j int) bool {
		left := int64(0)
		right := int64(0)
		if result.Events[i].EventID != nil {
			left = *result.Events[i].EventID
		}
		if result.Events[j].EventID != nil {
			right = *result.Events[j].EventID
		}
		return left < right
	})

	return result, nil
}

// scanTicketProduct scans ticket product.
func scanTicketProduct(row pgx.Row) (models.TicketProduct, error) {
	var out models.TicketProduct
	var inventoryLimit sql.NullInt32
	var createdBy sql.NullInt64
	if err := row.Scan(
		&out.ID,
		&out.EventID,
		&out.Name,
		&out.Type,
		&out.PriceCents,
		&inventoryLimit,
		&out.SoldCount,
		&out.IsActive,
		&createdBy,
		&out.CreatedAt,
		&out.UpdatedAt,
	); err != nil {
		return out, err
	}
	if inventoryLimit.Valid {
		value := int(inventoryLimit.Int32)
		out.InventoryLimit = &value
	}
	if createdBy.Valid {
		value := createdBy.Int64
		out.CreatedBy = &value
	}
	return out, nil
}

// scanTransferProduct scans transfer product.
func scanTransferProduct(row pgx.Row) (models.TransferProduct, error) {
	var out models.TransferProduct
	var inventoryLimit sql.NullInt32
	var createdBy sql.NullInt64
	var infoRaw []byte
	if err := row.Scan(
		&out.ID,
		&out.EventID,
		&out.Name,
		&out.Direction,
		&out.PriceCents,
		&infoRaw,
		&inventoryLimit,
		&out.SoldCount,
		&out.IsActive,
		&createdBy,
		&out.CreatedAt,
		&out.UpdatedAt,
	); err != nil {
		return out, err
	}
	out.Info = decodeJSONMap(infoRaw)
	if inventoryLimit.Valid {
		value := int(inventoryLimit.Int32)
		out.InventoryLimit = &value
	}
	if createdBy.Valid {
		value := createdBy.Int64
		out.CreatedBy = &value
	}
	return out, nil
}

// scanPromoCode scans promo code.
func scanPromoCode(row pgx.Row) (models.PromoCode, error) {
	var out models.PromoCode
	var usageLimit sql.NullInt32
	var activeFrom sql.NullTime
	var activeTo sql.NullTime
	var eventID sql.NullInt64
	var createdBy sql.NullInt64
	if err := row.Scan(
		&out.ID,
		&out.Code,
		&out.DiscountType,
		&out.Value,
		&usageLimit,
		&out.UsedCount,
		&activeFrom,
		&activeTo,
		&eventID,
		&out.IsActive,
		&createdBy,
		&out.CreatedAt,
		&out.UpdatedAt,
	); err != nil {
		return out, err
	}
	if usageLimit.Valid {
		value := int(usageLimit.Int32)
		out.UsageLimit = &value
	}
	out.ActiveFrom = nullTimeToPtr(activeFrom)
	out.ActiveTo = nullTimeToPtr(activeTo)
	if eventID.Valid {
		value := eventID.Int64
		out.EventID = &value
	}
	if createdBy.Valid {
		value := createdBy.Int64
		out.CreatedBy = &value
	}
	return out, nil
}

// scanOrder scans order.
func scanOrder(row pgx.Row) (models.Order, error) {
	var out models.Order
	var eventTitle sql.NullString
	var contactTelegram sql.NullString
	var contactName sql.NullString
	var contactPhone sql.NullString
	var paymentRef sql.NullString
	var paymentNotes sql.NullString
	var promoCodeID sql.NullString
	var confirmedAt sql.NullTime
	var canceledAt sql.NullTime
	var redeemedAt sql.NullTime
	var confirmedBy sql.NullInt64
	var canceledBy sql.NullInt64
	var canceledReason sql.NullString
	if err := row.Scan(
		&out.ID,
		&out.UserID,
		&out.EventID,
		&eventTitle,
		&contactTelegram,
		&contactName,
		&contactPhone,
		&out.Status,
		&out.PaymentMethod,
		&paymentRef,
		&paymentNotes,
		&promoCodeID,
		&out.SubtotalCents,
		&out.DiscountCents,
		&out.TotalCents,
		&out.Currency,
		&confirmedAt,
		&canceledAt,
		&redeemedAt,
		&confirmedBy,
		&canceledBy,
		&canceledReason,
		&out.CreatedAt,
		&out.UpdatedAt,
	); err != nil {
		return out, err
	}
	if eventTitle.Valid {
		out.EventTitle = eventTitle.String
	}
	if contactTelegram.Valid {
		out.ContactTelegram = contactTelegram.String
	}
	if contactName.Valid {
		out.ContactName = contactName.String
	}
	if contactPhone.Valid {
		out.ContactPhone = contactPhone.String
	}
	if paymentRef.Valid {
		out.PaymentReference = paymentRef.String
	}
	if paymentNotes.Valid {
		out.PaymentNotes = paymentNotes.String
	}
	if promoCodeID.Valid {
		value := promoCodeID.String
		out.PromoCodeID = &value
	}
	out.ConfirmedAt = nullTimeToPtr(confirmedAt)
	out.CanceledAt = nullTimeToPtr(canceledAt)
	out.RedeemedAt = nullTimeToPtr(redeemedAt)
	if confirmedBy.Valid {
		value := confirmedBy.Int64
		out.ConfirmedBy = &value
	}
	if canceledBy.Valid {
		value := canceledBy.Int64
		out.CanceledBy = &value
	}
	if canceledReason.Valid {
		out.CanceledReason = canceledReason.String
	}
	return out, nil
}

// scanOrderSummary scans order summary.
func scanOrderSummary(row pgx.Row) (models.OrderSummary, error) {
	var out models.OrderSummary
	var order models.Order
	var user models.OrderUserSummary
	var eventTitle sql.NullString
	var contactTelegram sql.NullString
	var contactName sql.NullString
	var contactPhone sql.NullString
	var paymentRef sql.NullString
	var paymentNotes sql.NullString
	var promoCodeID sql.NullString
	var confirmedAt sql.NullTime
	var canceledAt sql.NullTime
	var redeemedAt sql.NullTime
	var confirmedBy sql.NullInt64
	var canceledBy sql.NullInt64
	var canceledReason sql.NullString
	var firstName sql.NullString
	var lastName sql.NullString
	var username sql.NullString
	if err := row.Scan(
		&order.ID,
		&order.UserID,
		&order.EventID,
		&eventTitle,
		&contactTelegram,
		&contactName,
		&contactPhone,
		&order.Status,
		&order.PaymentMethod,
		&paymentRef,
		&paymentNotes,
		&promoCodeID,
		&order.SubtotalCents,
		&order.DiscountCents,
		&order.TotalCents,
		&order.Currency,
		&confirmedAt,
		&canceledAt,
		&redeemedAt,
		&confirmedBy,
		&canceledBy,
		&canceledReason,
		&order.CreatedAt,
		&order.UpdatedAt,
		&user.ID,
		&user.TelegramID,
		&firstName,
		&lastName,
		&username,
	); err != nil {
		return out, err
	}
	if eventTitle.Valid {
		order.EventTitle = eventTitle.String
	}
	if contactTelegram.Valid {
		order.ContactTelegram = contactTelegram.String
	}
	if contactName.Valid {
		order.ContactName = contactName.String
	}
	if contactPhone.Valid {
		order.ContactPhone = contactPhone.String
	}
	if paymentRef.Valid {
		order.PaymentReference = paymentRef.String
	}
	if paymentNotes.Valid {
		order.PaymentNotes = paymentNotes.String
	}
	if promoCodeID.Valid {
		value := promoCodeID.String
		order.PromoCodeID = &value
	}
	order.ConfirmedAt = nullTimeToPtr(confirmedAt)
	order.CanceledAt = nullTimeToPtr(canceledAt)
	order.RedeemedAt = nullTimeToPtr(redeemedAt)
	if confirmedBy.Valid {
		value := confirmedBy.Int64
		order.ConfirmedBy = &value
	}
	if canceledBy.Valid {
		value := canceledBy.Int64
		order.CanceledBy = &value
	}
	if canceledReason.Valid {
		order.CanceledReason = canceledReason.String
	}
	if firstName.Valid {
		user.FirstName = firstName.String
	}
	if lastName.Valid {
		user.LastName = lastName.String
	}
	if username.Valid {
		user.Username = username.String
	}
	out.Order = order
	out.User = &user
	return out, nil
}

// scanTransferOrderSummary scans admin transfer order summary.
func scanTransferOrderSummary(row pgx.Row) (models.TransferOrderSummary, error) {
	var out models.TransferOrderSummary
	var user models.OrderUserSummary
	var item models.OrderItem
	var eventTitle sql.NullString
	var contactTelegram sql.NullString
	var contactName sql.NullString
	var contactPhone sql.NullString
	var firstName sql.NullString
	var lastName sql.NullString
	var username sql.NullString
	var metaRaw []byte
	if err := row.Scan(
		&out.OrderID,
		&out.OrderStatus,
		&out.OrderCreatedAt,
		&out.EventID,
		&eventTitle,
		&out.UserID,
		&contactTelegram,
		&contactName,
		&contactPhone,
		&user.ID,
		&user.TelegramID,
		&firstName,
		&lastName,
		&username,
		&item.ID,
		&item.OrderID,
		&item.ItemType,
		&item.ProductID,
		&item.ProductRef,
		&item.Quantity,
		&item.UnitPriceCents,
		&item.LineTotalCents,
		&metaRaw,
		&item.CreatedAt,
	); err != nil {
		return out, err
	}
	if eventTitle.Valid {
		out.EventTitle = eventTitle.String
	}
	if contactTelegram.Valid {
		out.ContactTelegram = contactTelegram.String
	}
	if contactName.Valid {
		out.ContactName = contactName.String
	}
	if contactPhone.Valid {
		out.ContactPhone = contactPhone.String
	}
	if firstName.Valid {
		user.FirstName = firstName.String
	}
	if lastName.Valid {
		user.LastName = lastName.String
	}
	if username.Valid {
		user.Username = username.String
	}
	item.Meta = decodeJSONMap(metaRaw)
	out.User = &user
	out.Item = item
	return out, nil
}

// promoCodeForOrder returns the promo code text stored for an order.
func (r *Repository) promoCodeForOrder(ctx context.Context, q queryRunner, promoCodeID string) (string, error) {
	var code string
	if err := q.QueryRow(ctx, `
SELECT code
FROM promo_codes
WHERE id = $1::uuid;`, promoCodeID).Scan(&code); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return "", nil
		}
		return "", err
	}
	return strings.TrimSpace(code), nil
}

// scanOrderItem scans order item.
func scanOrderItem(row pgx.Row) (models.OrderItem, error) {
	var out models.OrderItem
	var metaRaw []byte
	if err := row.Scan(
		&out.ID,
		&out.OrderID,
		&out.ItemType,
		&out.ProductID,
		&out.ProductRef,
		&out.Quantity,
		&out.UnitPriceCents,
		&out.LineTotalCents,
		&metaRaw,
		&out.CreatedAt,
	); err != nil {
		return out, err
	}
	out.Meta = decodeJSONMap(metaRaw)
	return out, nil
}

// scanTicket scans ticket.
func scanTicket(row pgx.Row) (models.Ticket, error) {
	var out models.Ticket
	var qrPayload sql.NullString
	var qrPayloadHash sql.NullString
	var qrIssuedAt sql.NullTime
	var qrDeliveredAt sql.NullTime
	var qrDeliveryError sql.NullString
	var redeemedAt sql.NullTime
	var redeemedBy sql.NullInt64
	if err := row.Scan(
		&out.ID,
		&out.OrderID,
		&out.UserID,
		&out.EventID,
		&out.TicketType,
		&out.Quantity,
		&qrPayload,
		&qrPayloadHash,
		&qrIssuedAt,
		&qrDeliveredAt,
		&qrDeliveryError,
		&redeemedAt,
		&redeemedBy,
		&out.CreatedAt,
	); err != nil {
		return out, err
	}
	if qrPayload.Valid {
		out.QRPayload = qrPayload.String
	}
	if qrPayloadHash.Valid {
		out.QRPayloadHash = qrPayloadHash.String
	}
	out.QRIssuedAt = nullTimeToPtr(qrIssuedAt)
	out.QRDeliveredAt = nullTimeToPtr(qrDeliveredAt)
	if qrDeliveryError.Valid {
		out.QRDeliveryError = qrDeliveryError.String
	}
	out.RedeemedAt = nullTimeToPtr(redeemedAt)
	if redeemedBy.Valid {
		value := redeemedBy.Int64
		out.RedeemedBy = &value
	}
	return out, nil
}

// scanPaymentSettingsRow scans payment settings row.
func scanPaymentSettingsRow(row pgx.Row) (models.PaymentSettings, error) {
	var out models.PaymentSettings
	var updatedBy sql.NullInt64
	var createdAt sql.NullTime
	var updatedAt sql.NullTime
	if err := row.Scan(
		&out.Scope,
		&out.PhoneNumber,
		&out.USDTWallet,
		&out.USDTNetwork,
		&out.USDTMemo,
		&out.PaymentQRData,
		&out.PhoneEnabled,
		&out.USDTEnabled,
		&out.PaymentQREnabled,
		&out.SBPEnabled,
		&out.PhoneDescription,
		&out.USDTDescription,
		&out.QRDescription,
		&out.SBPDescription,
		&updatedBy,
		&createdAt,
		&updatedAt,
	); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			out.Scope = models.PaymentSettingsScopeTicket
			out.USDTNetwork = "TRC20"
			out.PhoneEnabled = true
			out.USDTEnabled = true
			out.PaymentQREnabled = true
			out.SBPEnabled = true
			return out, nil
		}
		return out, err
	}
	out.Scope = normalizePaymentSettingsScope(out.Scope)
	if strings.TrimSpace(out.USDTNetwork) == "" {
		out.USDTNetwork = "TRC20"
	}
	out.UpdatedBy = nullInt64ToPtr(updatedBy)
	out.CreatedAt = nullTimeToPtr(createdAt)
	out.UpdatedAt = nullTimeToPtr(updatedAt)
	return out, nil
}

// normalizePaymentSettingsScope returns the storage scope for payment settings.
func normalizePaymentSettingsScope(scope string) string {
	switch strings.ToUpper(strings.TrimSpace(scope)) {
	case models.PaymentSettingsScopeTransfer:
		return models.PaymentSettingsScopeTransfer
	default:
		return models.PaymentSettingsScopeTicket
	}
}

// mergeSelections merges selections.
func mergeSelections(items []models.OrderProductSelection) map[string]int {
	out := map[string]int{}
	for _, item := range items {
		id := strings.TrimSpace(item.ProductID)
		if id == "" || item.Quantity <= 0 {
			continue
		}
		if item.Quantity > 100 {
			item.Quantity = 100
		}
		out[id] += item.Quantity
	}
	return out
}

// isValidPaymentMethod reports whether valid payment method condition is met.
func isValidPaymentMethod(method string) bool {
	switch method {
	case models.PaymentMethodPhone, models.PaymentMethodUSDT, models.PaymentMethodQR, models.PaymentMethodTochkaSBPQR:
		return true
	default:
		return false
	}
}

// updateOrderToPaidCompatible updates order to paid compatible.
func (r *Repository) updateOrderToPaidCompatible(ctx context.Context, tx pgx.Tx, orderID string, confirmedBy interface{}) error {
	if _, err := tx.Exec(ctx, `SAVEPOINT confirm_order_status`); err != nil {
		return err
	}

	tryUpdate := func(status string) (int64, error) {
		cmd, err := tx.Exec(ctx, `
UPDATE orders
SET status = $2,
	confirmed_at = now(),
	confirmed_by = $3,
	updated_at = now()
WHERE id = $1::uuid AND status = $4;`, orderID, status, confirmedBy, models.OrderStatusPending)
		if err != nil {
			return 0, err
		}
		return cmd.RowsAffected(), nil
	}

	rows, err := tryUpdate(models.OrderStatusPaid)
	if err == nil {
		if _, releaseErr := tx.Exec(ctx, `RELEASE SAVEPOINT confirm_order_status`); releaseErr != nil {
			return releaseErr
		}
		if rows == 0 {
			return ErrOrderStateNotAllowed
		}
		return nil
	}

	if _, rbErr := tx.Exec(ctx, `ROLLBACK TO SAVEPOINT confirm_order_status`); rbErr != nil {
		return err
	}
	if !isOrdersStatusCheckViolation(err) {
		if _, releaseErr := tx.Exec(ctx, `RELEASE SAVEPOINT confirm_order_status`); releaseErr != nil {
			return releaseErr
		}
		return err
	}

	rows, err = tryUpdate("CONFIRMED")
	if err != nil {
		if _, releaseErr := tx.Exec(ctx, `RELEASE SAVEPOINT confirm_order_status`); releaseErr != nil {
			return releaseErr
		}
		return err
	}
	if _, releaseErr := tx.Exec(ctx, `RELEASE SAVEPOINT confirm_order_status`); releaseErr != nil {
		return releaseErr
	}
	if rows == 0 {
		return ErrOrderStateNotAllowed
	}
	return nil
}

// isOrdersStatusCheckViolation reports whether orders status check violation condition is met.
func isOrdersStatusCheckViolation(err error) bool {
	var pgErr *pgconn.PgError
	if !errors.As(err, &pgErr) {
		return false
	}
	if pgErr.Code != "23514" {
		return false
	}
	return strings.EqualFold(strings.TrimSpace(pgErr.ConstraintName), "orders_status_check")
}

// isPendingOrderStatus reports whether pending order status condition is met.
func isPendingOrderStatus(status string) bool {
	return strings.EqualFold(strings.TrimSpace(status), models.OrderStatusPending)
}

// isPaidOrderStatus reports whether paid order status condition is met.
func isPaidOrderStatus(status string) bool {
	normalized := strings.ToUpper(strings.TrimSpace(status))
	return normalized == models.OrderStatusPaid || normalized == "CONFIRMED"
}

// isRedeemedOrderStatus reports whether redeemed order status condition is met.
func isRedeemedOrderStatus(status string) bool {
	return strings.EqualFold(strings.TrimSpace(status), models.OrderStatusRedeemed)
}

// safeMap handles safe map.
func safeMap(input map[string]interface{}) map[string]interface{} {
	if input == nil {
		return map[string]interface{}{}
	}
	return input
}

// isTransferProductUniqueViolation reports duplicate transfer direction collisions.
func isTransferProductUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	if !errors.As(err, &pgErr) || pgErr.Code != "23505" {
		return false
	}
	name := strings.TrimSpace(pgErr.ConstraintName)
	return strings.EqualFold(name, transferProductDirectionConstraintName) ||
		strings.EqualFold(name, transferProductLandingConstraintName)
}

// decodeJSONMap decodes j s o n map.
func decodeJSONMap(raw []byte) map[string]interface{} {
	if len(raw) == 0 {
		return map[string]interface{}{}
	}
	out := map[string]interface{}{}
	if err := json.Unmarshal(raw, &out); err != nil {
		return map[string]interface{}{}
	}
	return out
}

// int64PtrOrNil handles int64 ptr or nil.
func int64PtrOrNil(value *int64) interface{} {
	if value == nil {
		return nil
	}
	return *value
}

// boolPtrOrNil handles bool ptr or nil.
func boolPtrOrNil(value *bool) interface{} {
	if value == nil {
		return nil
	}
	return *value
}

// nullIntPtr handles null int ptr.
func nullIntPtr(value *int) interface{} {
	if value == nil || *value <= 0 {
		return nil
	}
	return *value
}

// nullInt32ToIntPtr handles null int32 to int ptr.
func nullInt32ToIntPtr(value sql.NullInt32) *int {
	if !value.Valid {
		return nil
	}
	v := int(value.Int32)
	return &v
}

// nullTimeToPtr handles null time to ptr.
func nullTimeToPtr(value sql.NullTime) *time.Time {
	if !value.Valid {
		return nil
	}
	v := value.Time
	return &v
}

// nullInt64ToPtr handles null int64 to ptr.
func nullInt64ToPtr(value sql.NullInt64) *int64 {
	if !value.Valid {
		return nil
	}
	v := value.Int64
	return &v
}

// uuidPtrOrNil handles uuid ptr or nil.
func uuidPtrOrNil(value *string) interface{} {
	if value == nil || strings.TrimSpace(*value) == "" {
		return nil
	}
	return strings.TrimSpace(*value)
}
