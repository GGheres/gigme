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
)

var (
	ErrOrderNotFound         = errors.New("order not found")
	ErrOrderStateNotAllowed  = errors.New("order state not allowed")
	ErrInvalidProduct        = errors.New("invalid product selection")
	ErrPromoInvalid          = errors.New("promo code is invalid")
	ErrInventoryLimitReached = errors.New("inventory limit reached")
	ErrTicketAlreadyRedeemed = errors.New("ticket already redeemed")
	ErrTicketQRMismatch      = errors.New("ticket qr mismatch")
	ErrTicketNotFound        = errors.New("ticket not found")
)

type queryRunner interface {
	Query(context.Context, string, ...interface{}) (pgx.Rows, error)
	QueryRow(context.Context, string, ...interface{}) pgx.Row
}

func (r *Repository) ListTicketProducts(ctx context.Context, eventID *int64, active *bool) ([]models.TicketProduct, error) {
	rows, err := r.pool.Query(ctx, `
SELECT id::text, event_id, type, price_cents, inventory_limit, sold_count, is_active, created_by, created_at, updated_at
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

func (r *Repository) CreateTicketProduct(ctx context.Context, createdBy int64, in models.TicketProductInput) (models.TicketProduct, error) {
	row := r.pool.QueryRow(ctx, `
INSERT INTO ticket_products (event_id, type, price_cents, inventory_limit, is_active, created_by)
VALUES ($1, $2, $3, $4, $5, $6)
RETURNING id::text, event_id, type, price_cents, inventory_limit, sold_count, is_active, created_by, created_at, updated_at;`,
		in.EventID,
		strings.ToUpper(strings.TrimSpace(in.Type)),
		in.PriceCents,
		nullIntPtr(in.InventoryLimit),
		in.IsActive,
		nullInt64Ptr(&createdBy),
	)
	return scanTicketProduct(row)
}

func (r *Repository) UpdateTicketProduct(ctx context.Context, id string, patch models.TicketProductPatch) (models.TicketProduct, error) {
	row := r.pool.QueryRow(ctx, `
UPDATE ticket_products
SET price_cents = COALESCE($2, price_cents),
	inventory_limit = COALESCE($3, inventory_limit),
	is_active = COALESCE($4, is_active),
	updated_at = now()
WHERE id = $1::uuid
RETURNING id::text, event_id, type, price_cents, inventory_limit, sold_count, is_active, created_by, created_at, updated_at;`,
		id,
		int64PtrOrNil(patch.PriceCents),
		nullIntPtr(patch.InventoryLimit),
		boolPtrOrNil(patch.IsActive),
	)
	return scanTicketProduct(row)
}

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

func (r *Repository) ListTransferProducts(ctx context.Context, eventID *int64, active *bool) ([]models.TransferProduct, error) {
	rows, err := r.pool.Query(ctx, `
SELECT id::text, event_id, direction, price_cents, info_json, inventory_limit, sold_count, is_active, created_by, created_at, updated_at
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
	return items, rows.Err()
}

func (r *Repository) CreateTransferProduct(ctx context.Context, createdBy int64, in models.TransferProductInput) (models.TransferProduct, error) {
	infoJSON, _ := json.Marshal(safeMap(in.Info))
	row := r.pool.QueryRow(ctx, `
INSERT INTO transfer_products (event_id, direction, price_cents, info_json, inventory_limit, is_active, created_by)
VALUES ($1, $2, $3, $4::jsonb, $5, $6, $7)
RETURNING id::text, event_id, direction, price_cents, info_json, inventory_limit, sold_count, is_active, created_by, created_at, updated_at;`,
		in.EventID,
		strings.ToUpper(strings.TrimSpace(in.Direction)),
		in.PriceCents,
		infoJSON,
		nullIntPtr(in.InventoryLimit),
		in.IsActive,
		nullInt64Ptr(&createdBy),
	)
	return scanTransferProduct(row)
}

func (r *Repository) UpdateTransferProduct(ctx context.Context, id string, patch models.TransferProductPatch) (models.TransferProduct, error) {
	var infoRaw interface{}
	if patch.Info != nil {
		buf, _ := json.Marshal(patch.Info)
		infoRaw = buf
	}

	row := r.pool.QueryRow(ctx, `
UPDATE transfer_products
SET price_cents = COALESCE($2, price_cents),
	info_json = COALESCE($3::jsonb, info_json),
	inventory_limit = COALESCE($4, inventory_limit),
	is_active = COALESCE($5, is_active),
	updated_at = now()
WHERE id = $1::uuid
RETURNING id::text, event_id, direction, price_cents, info_json, inventory_limit, sold_count, is_active, created_by, created_at, updated_at;`,
		id,
		int64PtrOrNil(patch.PriceCents),
		infoRaw,
		nullIntPtr(patch.InventoryLimit),
		boolPtrOrNil(patch.IsActive),
	)
	return scanTransferProduct(row)
}

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

func (r *Repository) ListEventProductsForPurchase(ctx context.Context, eventID int64) ([]models.TicketProduct, []models.TransferProduct, error) {
	eid := eventID
	onlyActive := true
	tickets, err := r.ListTicketProducts(ctx, &eid, &onlyActive)
	if err != nil {
		return nil, nil, err
	}
	transfers, err := r.ListTransferProducts(ctx, &eid, &onlyActive)
	if err != nil {
		return nil, nil, err
	}
	return tickets, transfers, nil
}

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
	if len(ticketSelections) == 0 {
		return out, ErrInvalidProduct
	}
	transferSelections := mergeSelections(params.TransferItems)

	err := r.WithTx(ctx, func(tx pgx.Tx) error {
		return r.createOrderTx(ctx, tx, params, ticketSelections, transferSelections, &out)
	})
	if err != nil {
		return models.OrderDetail{}, err
	}
	return out, nil
}

func (r *Repository) createOrderTx(
	ctx context.Context,
	tx pgx.Tx,
	params models.CreateOrderParams,
	ticketSelections map[string]int,
	transferSelections map[string]int,
	out *models.OrderDetail,
) error {
	var eventTitle string
	if err := tx.QueryRow(ctx, `SELECT title FROM events WHERE id = $1`, params.EventID).Scan(&eventTitle); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrInvalidProduct
		}
		return err
	}

	type itemDraft struct {
		ItemType       string
		ProductID      string
		ProductRef     string
		Quantity       int
		UnitPriceCents int64
		LineTotalCents int64
		Meta           map[string]interface{}
	}
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
		var direction string
		var priceCents int64
		var isActive bool
		var infoRaw []byte
		if err := tx.QueryRow(ctx, `
SELECT id::text, event_id, direction, price_cents, is_active, info_json
FROM transfer_products
WHERE id = $1::uuid
FOR UPDATE;`, productID).Scan(&dbID, &eventID, &direction, &priceCents, &isActive, &infoRaw); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return ErrInvalidProduct
			}
			return err
		}
		if eventID != params.EventID || !isActive {
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
				"info":      decodeJSONMap(infoRaw),
			},
		})
	}

	if subtotal <= 0 {
		return ErrInvalidProduct
	}

	var promoCodeID *string
	discount := int64(0)
	promoCode := strings.ToUpper(strings.TrimSpace(params.PromoCode))
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

	row := tx.QueryRow(ctx, `
INSERT INTO orders (
	user_id,
	event_id,
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
	$11
)
RETURNING id::text, user_id, event_id, ''::text, status, payment_method, payment_reference, payment_notes, promo_code_id::text, subtotal_cents, discount_cents, total_cents, currency, confirmed_at, canceled_at, redeemed_at, confirmed_by, canceled_by, canceled_reason, created_at, updated_at;`,
		params.UserID,
		params.EventID,
		models.OrderStatusPending,
		params.PaymentMethod,
		nullString(strings.TrimSpace(params.PaymentReference)),
		uuidPtrOrNil(promoCodeID),
		subtotal,
		discount,
		total,
		"USD",
		nullString("waiting_for_manual_confirmation"),
	)
	order, err := scanOrder(row)
	if err != nil {
		return err
	}
	order.EventTitle = eventTitle

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
RETURNING id::text, order_id::text, user_id, event_id, ticket_type, quantity, qr_payload, qr_payload_hash, qr_issued_at, redeemed_at, redeemed_by, created_at;`,
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

func (r *Repository) GetOrderDetail(ctx context.Context, orderID string, includeUser bool) (models.OrderDetail, error) {
	return r.fetchOrderDetail(ctx, r.pool, orderID, includeUser)
}

func (r *Repository) fetchOrderDetail(ctx context.Context, q queryRunner, orderID string, includeUser bool) (models.OrderDetail, error) {
	var out models.OrderDetail
	order, err := scanOrder(q.QueryRow(ctx, `
SELECT
	o.id::text,
	o.user_id,
	o.event_id,
	e.title,
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
	out.Order = order

	if includeUser {
		var user models.OrderUserSummary
		if err := q.QueryRow(ctx, `
SELECT id, telegram_id, first_name, last_name, username
FROM users
WHERE id = $1;`, order.UserID).Scan(&user.ID, &user.TelegramID, &user.FirstName, &user.LastName, &user.Username); err != nil {
			if !errors.Is(err, pgx.ErrNoRows) {
				return out, err
			}
		} else {
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
	defer itemRows.Close()
	items := make([]models.OrderItem, 0)
	for itemRows.Next() {
		item, err := scanOrderItem(itemRows)
		if err != nil {
			return out, err
		}
		items = append(items, item)
	}
	if err := itemRows.Err(); err != nil {
		return out, err
	}
	out.Items = items

	ticketRows, err := q.Query(ctx, `
SELECT id::text, order_id::text, user_id, event_id, ticket_type, quantity, qr_payload, qr_payload_hash, qr_issued_at, redeemed_at, redeemed_by, created_at
FROM tickets
WHERE order_id = $1::uuid
ORDER BY created_at ASC, id ASC;`, orderID)
	if err != nil {
		return out, err
	}
	defer ticketRows.Close()
	tickets := make([]models.Ticket, 0)
	for ticketRows.Next() {
		ticket, err := scanTicket(ticketRows)
		if err != nil {
			return out, err
		}
		tickets = append(tickets, ticket)
	}
	if err := ticketRows.Err(); err != nil {
		return out, err
	}
	out.Tickets = tickets
	return out, nil
}

func (r *Repository) ConfirmOrder(ctx context.Context, orderID string, adminID int64, qrSecret string) (models.OrderDetail, int64, error) {
	var detail models.OrderDetail
	var telegramID int64
	secret := strings.TrimSpace(qrSecret)
	if secret == "" {
		return detail, 0, fmt.Errorf("qr secret is required")
	}

	err := r.WithTx(ctx, func(tx pgx.Tx) error {
		var orderStatus string
		var userID int64
		if err := tx.QueryRow(ctx, `
SELECT status, user_id
FROM orders
WHERE id = $1::uuid
FOR UPDATE;`, orderID).Scan(&orderStatus, &userID); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return ErrOrderNotFound
			}
			return err
		}
		if orderStatus != models.OrderStatusPending {
			return ErrOrderStateNotAllowed
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
		defer itemRows.Close()
		for itemRows.Next() {
			var itemType string
			var productID string
			var quantity int
			if err := itemRows.Scan(&itemType, &productID, &quantity); err != nil {
				return err
			}
			switch itemType {
			case models.ItemTypeTicket:
				cmd, err := tx.Exec(ctx, `
UPDATE ticket_products
SET sold_count = sold_count + $2,
	updated_at = now()
WHERE id = $1::uuid
	AND (inventory_limit IS NULL OR sold_count + $2 <= inventory_limit);`, productID, quantity)
				if err != nil {
					return err
				}
				if cmd.RowsAffected() == 0 {
					return ErrInventoryLimitReached
				}
			case models.ItemTypeTransfer:
				cmd, err := tx.Exec(ctx, `
UPDATE transfer_products
SET sold_count = sold_count + $2,
	updated_at = now()
WHERE id = $1::uuid
	AND (inventory_limit IS NULL OR sold_count + $2 <= inventory_limit);`, productID, quantity)
				if err != nil {
					return err
				}
				if cmd.RowsAffected() == 0 {
					return ErrInventoryLimitReached
				}
			}
		}
		if err := itemRows.Err(); err != nil {
			return err
		}

		cmd, err := tx.Exec(ctx, `
UPDATE orders
SET status = $2,
	confirmed_at = now(),
	confirmed_by = $3,
	updated_at = now()
WHERE id = $1::uuid
	AND status = $4;`, orderID, models.OrderStatusConfirmed, adminID, models.OrderStatusPending)
		if err != nil {
			return err
		}
		if cmd.RowsAffected() == 0 {
			return ErrOrderStateNotAllowed
		}

		ticketRows, err := tx.Query(ctx, `
SELECT id::text, user_id, event_id, ticket_type, quantity
FROM tickets
WHERE order_id = $1::uuid
ORDER BY created_at ASC
FOR UPDATE;`, orderID)
		if err != nil {
			return err
		}
		defer ticketRows.Close()
		now := time.Now().UTC()
		for ticketRows.Next() {
			var ticketID string
			var ticketUserID int64
			var eventID int64
			var ticketType string
			var quantity int
			if err := ticketRows.Scan(&ticketID, &ticketUserID, &eventID, &ticketType, &quantity); err != nil {
				return err
			}
			nonce, err := ticketing.NewNonce(16)
			if err != nil {
				return err
			}
			payload := ticketing.BuildPayload(ticketID, eventID, ticketUserID, ticketType, quantity, now, nonce)
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
WHERE id = $1::uuid;`, ticketID, token, hash, now); err != nil {
				return err
			}
		}
		if err := ticketRows.Err(); err != nil {
			return err
		}

		if err := tx.QueryRow(ctx, `SELECT telegram_id FROM users WHERE id = $1`, userID).Scan(&telegramID); err != nil {
			return err
		}

		detail, err = r.fetchOrderDetail(ctx, tx, orderID, true)
		return err
	})
	if err != nil {
		return models.OrderDetail{}, 0, err
	}
	return detail, telegramID, nil
}

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

		if status == models.OrderStatusConfirmed {
			rows, err := tx.Query(ctx, `
SELECT item_type, product_id::text, quantity
FROM order_items
WHERE order_id = $1::uuid
ORDER BY id ASC
FOR UPDATE;`, orderID)
			if err != nil {
				return err
			}
			defer rows.Close()
			for rows.Next() {
				var itemType string
				var productID string
				var quantity int
				if err := rows.Scan(&itemType, &productID, &quantity); err != nil {
					return err
				}
				switch itemType {
				case models.ItemTypeTicket:
					if _, err := tx.Exec(ctx, `
UPDATE ticket_products
SET sold_count = GREATEST(0, sold_count - $2),
	updated_at = now()
WHERE id = $1::uuid;`, productID, quantity); err != nil {
						return err
					}
				case models.ItemTypeTransfer:
					if _, err := tx.Exec(ctx, `
UPDATE transfer_products
SET sold_count = GREATEST(0, sold_count - $2),
	updated_at = now()
WHERE id = $1::uuid;`, productID, quantity); err != nil {
						return err
					}
				}
			}
			if err := rows.Err(); err != nil {
				return err
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
		if orderStatus != models.OrderStatusConfirmed && orderStatus != models.OrderStatusRedeemed {
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
	AND status IN ($3, $4);`, ticket.OrderID, models.OrderStatusRedeemed, models.OrderStatusConfirmed, models.OrderStatusRedeemed); err != nil {
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

func (r *Repository) ListMyTickets(ctx context.Context, userID int64, eventID *int64) ([]models.Ticket, error) {
	rows, err := r.pool.Query(ctx, `
SELECT id::text, order_id::text, user_id, event_id, ticket_type, quantity, qr_payload, qr_payload_hash, qr_issued_at, redeemed_at, redeemed_by, created_at
FROM tickets
WHERE user_id = $1
	AND ($2::bigint IS NULL OR event_id = $2)
ORDER BY created_at DESC;`, userID, nullInt64Ptr(eventID))
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	items := make([]models.Ticket, 0)
	for rows.Next() {
		ticket, err := scanTicket(rows)
		if err != nil {
			return nil, err
		}
		items = append(items, ticket)
	}
	return items, rows.Err()
}

func (r *Repository) GetTicketStats(ctx context.Context, eventID *int64) (models.TicketStats, error) {
	rows, err := r.pool.Query(ctx, `
SELECT
	o.id::text,
	o.event_id,
	e.title,
	o.status,
	o.total_cents,
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
			&row.TotalCents,
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
			PurchasedAmountCents:    globalBucket.PurchasedAmountCents,
			RedeemedAmountCents:     globalBucket.RedeemedAmountCents,
			TicketTypeCounts:        globalBucket.TicketTypeCounts,
			TransferDirectionCounts: globalBucket.TransferDirectionCounts,
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
			EventID:                 &eventIDVal,
			EventTitle:              bucket.EventTitle,
			PurchasedAmountCents:    bucket.PurchasedAmountCents,
			RedeemedAmountCents:     bucket.RedeemedAmountCents,
			TicketTypeCounts:        bucket.TicketTypeCounts,
			TransferDirectionCounts: bucket.TransferDirectionCounts,
		})
	}
	return result, nil
}

func scanTicketProduct(row pgx.Row) (models.TicketProduct, error) {
	var out models.TicketProduct
	var inventoryLimit sql.NullInt32
	var createdBy sql.NullInt64
	if err := row.Scan(
		&out.ID,
		&out.EventID,
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

func scanTransferProduct(row pgx.Row) (models.TransferProduct, error) {
	var out models.TransferProduct
	var inventoryLimit sql.NullInt32
	var createdBy sql.NullInt64
	var infoRaw []byte
	if err := row.Scan(
		&out.ID,
		&out.EventID,
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

func scanOrder(row pgx.Row) (models.Order, error) {
	var out models.Order
	var eventTitle sql.NullString
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

func scanOrderSummary(row pgx.Row) (models.OrderSummary, error) {
	var out models.OrderSummary
	var order models.Order
	var user models.OrderUserSummary
	var eventTitle sql.NullString
	var paymentRef sql.NullString
	var paymentNotes sql.NullString
	var promoCodeID sql.NullString
	var confirmedAt sql.NullTime
	var canceledAt sql.NullTime
	var redeemedAt sql.NullTime
	var confirmedBy sql.NullInt64
	var canceledBy sql.NullInt64
	var canceledReason sql.NullString
	var username sql.NullString
	if err := row.Scan(
		&order.ID,
		&order.UserID,
		&order.EventID,
		&eventTitle,
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
		&user.FirstName,
		&user.LastName,
		&username,
	); err != nil {
		return out, err
	}
	if eventTitle.Valid {
		order.EventTitle = eventTitle.String
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
	if username.Valid {
		user.Username = username.String
	}
	out.Order = order
	out.User = &user
	return out, nil
}

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

func scanTicket(row pgx.Row) (models.Ticket, error) {
	var out models.Ticket
	var qrPayload sql.NullString
	var qrPayloadHash sql.NullString
	var qrIssuedAt sql.NullTime
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
	out.RedeemedAt = nullTimeToPtr(redeemedAt)
	if redeemedBy.Valid {
		value := redeemedBy.Int64
		out.RedeemedBy = &value
	}
	return out, nil
}

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

func isValidPaymentMethod(method string) bool {
	switch method {
	case models.PaymentMethodPhone, models.PaymentMethodUSDT, models.PaymentMethodQR:
		return true
	default:
		return false
	}
}

func safeMap(input map[string]interface{}) map[string]interface{} {
	if input == nil {
		return map[string]interface{}{}
	}
	return input
}

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

func int64PtrOrNil(value *int64) interface{} {
	if value == nil {
		return nil
	}
	return *value
}

func boolPtrOrNil(value *bool) interface{} {
	if value == nil {
		return nil
	}
	return *value
}

func nullIntPtr(value *int) interface{} {
	if value == nil || *value <= 0 {
		return nil
	}
	return *value
}

func nullInt32ToIntPtr(value sql.NullInt32) *int {
	if !value.Valid {
		return nil
	}
	v := int(value.Int32)
	return &v
}

func nullTimeToPtr(value sql.NullTime) *time.Time {
	if !value.Valid {
		return nil
	}
	v := value.Time
	return &v
}

func nullInt64ToPtr(value sql.NullInt64) *int64 {
	if !value.Valid {
		return nil
	}
	v := value.Int64
	return &v
}

func uuidPtrOrNil(value *string) interface{} {
	if value == nil || strings.TrimSpace(*value) == "" {
		return nil
	}
	return strings.TrimSpace(*value)
}
