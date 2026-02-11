package handlers

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"gigme/backend/internal/http/middleware"
	"gigme/backend/internal/models"
	"gigme/backend/internal/repository"
	"gigme/backend/internal/ticketing"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
)

type orderSelectionRequest struct {
	ProductID string `json:"productId"`
	Quantity  int    `json:"quantity"`
}

type createOrderRequest struct {
	EventID          int64                   `json:"eventId"`
	PaymentMethod    string                  `json:"paymentMethod"`
	PaymentReference string                  `json:"paymentReference"`
	TicketItems      []orderSelectionRequest `json:"ticketItems"`
	TransferItems    []orderSelectionRequest `json:"transferItems"`
	PromoCode        string                  `json:"promoCode"`
}

type validatePromoRequest struct {
	EventID       int64  `json:"eventId"`
	Code          string `json:"code"`
	SubtotalCents int64  `json:"subtotalCents"`
}

type cancelOrderRequest struct {
	Reason string `json:"reason"`
}

type redeemTicketRequest struct {
	QRPayload string `json:"qrPayload"`
}

type listOrdersResponse struct {
	Items []models.OrderSummary `json:"items"`
	Total int                   `json:"total"`
}

type ticketProductsResponse struct {
	Tickets   []models.TicketProduct   `json:"tickets"`
	Transfers []models.TransferProduct `json:"transfers"`
}

type promoCodesResponse struct {
	Items []models.PromoCode `json:"items"`
}

type ticketProductsListResponse struct {
	Items []models.TicketProduct `json:"items"`
}

type transferProductsListResponse struct {
	Items []models.TransferProduct `json:"items"`
}

type myTicketsResponse struct {
	Items []models.Ticket `json:"items"`
}

func (h *Handler) CreateOrder(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	userID, ok := middleware.UserIDFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	var req createOrderRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		logger.Warn("create_order", "status", "invalid_json")
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	detail, err := h.repo.CreateOrder(ctx, models.CreateOrderParams{
		UserID:           userID,
		EventID:          req.EventID,
		PaymentMethod:    strings.ToUpper(strings.TrimSpace(req.PaymentMethod)),
		PaymentReference: strings.TrimSpace(req.PaymentReference),
		TicketItems:      mapSelections(req.TicketItems),
		TransferItems:    mapSelections(req.TransferItems),
		PromoCode:        strings.TrimSpace(req.PromoCode),
	})
	if err != nil {
		h.handleTicketingError(logger, w, "create_order", err)
		return
	}
	detail.PaymentInstructions = h.buildPaymentInstructions(detail.Order)
	writeJSON(w, http.StatusCreated, detail)
}

func (h *Handler) ValidatePromoCode(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	var req validatePromoRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	if req.EventID <= 0 || strings.TrimSpace(req.Code) == "" || req.SubtotalCents <= 0 {
		writeError(w, http.StatusBadRequest, "eventId, code and subtotalCents are required")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	result, err := h.repo.ValidatePromoCode(ctx, req.EventID, req.Code, req.SubtotalCents)
	if err != nil {
		logger.Error("validate_promo", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	writeJSON(w, http.StatusOK, result)
}

func (h *Handler) ListEventProducts(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	eventID, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil || eventID <= 0 {
		writeError(w, http.StatusBadRequest, "invalid event id")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	tickets, transfers, err := h.repo.ListEventProductsForPurchase(ctx, eventID)
	if err != nil {
		logger.Error("list_event_products", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	writeJSON(w, http.StatusOK, ticketProductsResponse{Tickets: tickets, Transfers: transfers})
}

func (h *Handler) ListMyOrders(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	userID, ok := middleware.UserIDFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	limit := parseIntQuery(r, "limit", 50)
	offset := parseIntQuery(r, "offset", 0)

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	items, total, err := h.repo.ListMyOrders(ctx, userID, limit, offset)
	if err != nil {
		logger.Error("list_my_orders", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	writeJSON(w, http.StatusOK, listOrdersResponse{Items: items, Total: total})
}

func (h *Handler) ListMyTickets(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	userID, ok := middleware.UserIDFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	var eventID *int64
	if raw := strings.TrimSpace(r.URL.Query().Get("event_id")); raw != "" {
		parsed, err := strconv.ParseInt(raw, 10, 64)
		if err != nil || parsed <= 0 {
			writeError(w, http.StatusBadRequest, "invalid event_id")
			return
		}
		eventID = &parsed
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	items, err := h.repo.ListMyTickets(ctx, userID, eventID)
	if err != nil {
		logger.Error("list_my_tickets", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	writeJSON(w, http.StatusOK, myTicketsResponse{Items: items})
}

func (h *Handler) ListAdminOrders(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_list_orders"); !ok {
		return
	}
	limit := parseIntQuery(r, "limit", 50)
	offset := parseIntQuery(r, "offset", 0)
	status := strings.ToUpper(strings.TrimSpace(r.URL.Query().Get("status")))

	var eventID *int64
	if raw := strings.TrimSpace(r.URL.Query().Get("event_id")); raw != "" {
		parsed, err := strconv.ParseInt(raw, 10, 64)
		if err != nil || parsed <= 0 {
			writeError(w, http.StatusBadRequest, "invalid event_id")
			return
		}
		eventID = &parsed
	}

	var from *time.Time
	if raw := strings.TrimSpace(r.URL.Query().Get("from")); raw != "" {
		parsed, err := time.Parse(time.RFC3339, raw)
		if err != nil {
			writeError(w, http.StatusBadRequest, "invalid from")
			return
		}
		from = &parsed
	}
	var to *time.Time
	if raw := strings.TrimSpace(r.URL.Query().Get("to")); raw != "" {
		parsed, err := time.Parse(time.RFC3339, raw)
		if err != nil {
			writeError(w, http.StatusBadRequest, "invalid to")
			return
		}
		to = &parsed
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	items, total, err := h.repo.ListOrders(ctx, eventID, status, from, to, limit, offset)
	if err != nil {
		logger.Error("admin_list_orders", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	writeJSON(w, http.StatusOK, listOrdersResponse{Items: items, Total: total})
}

func (h *Handler) GetAdminOrder(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_get_order"); !ok {
		return
	}
	orderID := strings.TrimSpace(chi.URLParam(r, "id"))
	if orderID == "" {
		writeError(w, http.StatusBadRequest, "invalid order id")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	detail, err := h.repo.GetOrderDetail(ctx, orderID, true)
	if err != nil {
		h.handleTicketingError(logger, w, "admin_get_order", err)
		return
	}
	detail.PaymentInstructions = h.buildPaymentInstructions(detail.Order)
	writeJSON(w, http.StatusOK, detail)
}

func (h *Handler) ConfirmOrder(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_confirm_order"); !ok {
		return
	}
	adminID, ok := middleware.UserIDFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	orderID := strings.TrimSpace(chi.URLParam(r, "id"))
	if orderID == "" {
		writeError(w, http.StatusBadRequest, "invalid order id")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	detail, telegramID, err := h.repo.ConfirmOrder(ctx, orderID, adminID, h.cfg.HMACSecret)
	if err != nil {
		h.handleTicketingError(logger, w, "admin_confirm_order", err)
		return
	}
	detail.PaymentInstructions = h.buildPaymentInstructions(detail.Order)

	if telegramID > 0 {
		for _, ticket := range detail.Tickets {
			if strings.TrimSpace(ticket.QRPayload) == "" {
				continue
			}
			if err := h.sendTicketQrToBot(telegramID, ticket); err != nil {
				logger.Warn("admin_confirm_order", "status", "ticket_delivery_failed", "ticket_id", ticket.ID, "telegram_id", telegramID, "error", err)
			}
		}
	}

	writeJSON(w, http.StatusOK, detail)
}

func (h *Handler) CancelOrder(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_cancel_order"); !ok {
		return
	}
	adminID, ok := middleware.UserIDFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	orderID := strings.TrimSpace(chi.URLParam(r, "id"))
	if orderID == "" {
		writeError(w, http.StatusBadRequest, "invalid order id")
		return
	}

	var req cancelOrderRequest
	_ = json.NewDecoder(r.Body).Decode(&req)

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	detail, err := h.repo.CancelOrder(ctx, orderID, adminID, req.Reason)
	if err != nil {
		h.handleTicketingError(logger, w, "admin_cancel_order", err)
		return
	}
	detail.PaymentInstructions = h.buildPaymentInstructions(detail.Order)
	writeJSON(w, http.StatusOK, detail)
}

func (h *Handler) RedeemTicket(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_redeem_ticket"); !ok {
		return
	}
	adminID, ok := middleware.UserIDFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	ticketID := strings.TrimSpace(chi.URLParam(r, "id"))
	if ticketID == "" {
		writeError(w, http.StatusBadRequest, "invalid ticket id")
		return
	}

	var req redeemTicketRequest
	_ = json.NewDecoder(r.Body).Decode(&req)

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	result, err := h.repo.RedeemTicket(ctx, ticketID, adminID, strings.TrimSpace(req.QRPayload), h.cfg.HMACSecret)
	if err != nil {
		h.handleTicketingError(logger, w, "admin_redeem_ticket", err)
		return
	}
	writeJSON(w, http.StatusOK, result)
}

func (h *Handler) AdminStats(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_stats"); !ok {
		return
	}

	var eventID *int64
	if raw := strings.TrimSpace(r.URL.Query().Get("event_id")); raw != "" {
		parsed, err := strconv.ParseInt(raw, 10, 64)
		if err != nil || parsed <= 0 {
			writeError(w, http.StatusBadRequest, "invalid event_id")
			return
		}
		eventID = &parsed
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	stats, err := h.repo.GetTicketStats(ctx, eventID)
	if err != nil {
		logger.Error("admin_stats", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	writeJSON(w, http.StatusOK, stats)
}

func (h *Handler) ListAdminTicketProducts(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_list_ticket_products"); !ok {
		return
	}
	eventID, active, err := parseProductFilters(r)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	items, err := h.repo.ListTicketProducts(ctx, eventID, active)
	if err != nil {
		logger.Error("admin_list_ticket_products", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	writeJSON(w, http.StatusOK, ticketProductsListResponse{Items: items})
}

func (h *Handler) CreateAdminTicketProduct(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_create_ticket_product"); !ok {
		return
	}
	adminID, ok := middleware.UserIDFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	var req models.TicketProductInput
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	item, err := h.repo.CreateTicketProduct(ctx, adminID, req)
	if err != nil {
		h.handleTicketingError(logger, w, "admin_create_ticket_product", err)
		return
	}
	writeJSON(w, http.StatusCreated, item)
}

func (h *Handler) PatchAdminTicketProduct(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_patch_ticket_product"); !ok {
		return
	}
	id := strings.TrimSpace(chi.URLParam(r, "id"))
	if id == "" {
		writeError(w, http.StatusBadRequest, "invalid product id")
		return
	}
	var req models.TicketProductPatch
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	item, err := h.repo.UpdateTicketProduct(ctx, id, req)
	if err != nil {
		h.handleTicketingError(logger, w, "admin_patch_ticket_product", err)
		return
	}
	writeJSON(w, http.StatusOK, item)
}

func (h *Handler) DeleteAdminTicketProduct(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_delete_ticket_product"); !ok {
		return
	}
	id := strings.TrimSpace(chi.URLParam(r, "id"))
	if id == "" {
		writeError(w, http.StatusBadRequest, "invalid product id")
		return
	}
	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	if err := h.repo.DeleteTicketProduct(ctx, id); err != nil {
		h.handleTicketingError(logger, w, "admin_delete_ticket_product", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (h *Handler) ListAdminTransferProducts(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_list_transfer_products"); !ok {
		return
	}
	eventID, active, err := parseProductFilters(r)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	items, err := h.repo.ListTransferProducts(ctx, eventID, active)
	if err != nil {
		logger.Error("admin_list_transfer_products", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	writeJSON(w, http.StatusOK, transferProductsListResponse{Items: items})
}

func (h *Handler) CreateAdminTransferProduct(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_create_transfer_product"); !ok {
		return
	}
	adminID, ok := middleware.UserIDFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	var req models.TransferProductInput
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	item, err := h.repo.CreateTransferProduct(ctx, adminID, req)
	if err != nil {
		h.handleTicketingError(logger, w, "admin_create_transfer_product", err)
		return
	}
	writeJSON(w, http.StatusCreated, item)
}

func (h *Handler) PatchAdminTransferProduct(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_patch_transfer_product"); !ok {
		return
	}
	id := strings.TrimSpace(chi.URLParam(r, "id"))
	if id == "" {
		writeError(w, http.StatusBadRequest, "invalid product id")
		return
	}
	var req models.TransferProductPatch
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	item, err := h.repo.UpdateTransferProduct(ctx, id, req)
	if err != nil {
		h.handleTicketingError(logger, w, "admin_patch_transfer_product", err)
		return
	}
	writeJSON(w, http.StatusOK, item)
}

func (h *Handler) DeleteAdminTransferProduct(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_delete_transfer_product"); !ok {
		return
	}
	id := strings.TrimSpace(chi.URLParam(r, "id"))
	if id == "" {
		writeError(w, http.StatusBadRequest, "invalid product id")
		return
	}
	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	if err := h.repo.DeleteTransferProduct(ctx, id); err != nil {
		h.handleTicketingError(logger, w, "admin_delete_transfer_product", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (h *Handler) ListAdminPromoCodes(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_list_promo_codes"); !ok {
		return
	}
	eventID, active, err := parseProductFilters(r)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	items, err := h.repo.ListPromoCodes(ctx, eventID, active)
	if err != nil {
		logger.Error("admin_list_promo_codes", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	writeJSON(w, http.StatusOK, promoCodesResponse{Items: items})
}

func (h *Handler) CreateAdminPromoCode(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_create_promo_code"); !ok {
		return
	}
	adminID, ok := middleware.UserIDFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	var req models.PromoCodeInput
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	item, err := h.repo.CreatePromoCode(ctx, adminID, req)
	if err != nil {
		h.handleTicketingError(logger, w, "admin_create_promo_code", err)
		return
	}
	writeJSON(w, http.StatusCreated, item)
}

func (h *Handler) PatchAdminPromoCode(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_patch_promo_code"); !ok {
		return
	}
	id := strings.TrimSpace(chi.URLParam(r, "id"))
	if id == "" {
		writeError(w, http.StatusBadRequest, "invalid promo id")
		return
	}
	var req models.PromoCodePatch
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	item, err := h.repo.UpdatePromoCode(ctx, id, req)
	if err != nil {
		h.handleTicketingError(logger, w, "admin_patch_promo_code", err)
		return
	}
	writeJSON(w, http.StatusOK, item)
}

func (h *Handler) DeleteAdminPromoCode(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_delete_promo_code"); !ok {
		return
	}
	id := strings.TrimSpace(chi.URLParam(r, "id"))
	if id == "" {
		writeError(w, http.StatusBadRequest, "invalid promo id")
		return
	}
	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	if err := h.repo.DeletePromoCode(ctx, id); err != nil {
		h.handleTicketingError(logger, w, "admin_delete_promo_code", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (h *Handler) sendTicketQrToBot(userTelegramID int64, ticket models.Ticket) error {
	if h.telegram == nil {
		return nil
	}
	payload := strings.TrimSpace(ticket.QRPayload)
	if payload == "" {
		return nil
	}
	qrBytes, err := ticketing.GenerateQRImagePNG(payload, 420)
	if err != nil {
		return err
	}
	caption := fmt.Sprintf("Ticket %s\nType: %s\nQty: %d", ticket.ID, ticket.TicketType, ticket.Quantity)
	if err := h.telegram.SendPhotoBytes(userTelegramID, fmt.Sprintf("ticket-%s.png", ticket.ID), qrBytes, caption, nil); err != nil {
		return h.telegram.SendMessage(userTelegramID, fmt.Sprintf("Ticket %s\nQR payload: %s", ticket.ID, payload))
	}
	return nil
}

func (h *Handler) buildPaymentInstructions(order models.Order) models.PaymentInstructions {
	amountText := formatAmount(order.TotalCents)
	instructions := models.PaymentInstructions{
		AmountCents: order.TotalCents,
		Currency:    order.Currency,
	}
	switch order.PaymentMethod {
	case models.PaymentMethodPhone:
		instructions.PhoneNumber = strings.TrimSpace(h.cfg.PhoneNumber)
		instructions.DisplayMessage = fmt.Sprintf("Transfer %s to phone number %s and click I paid.", amountText, instructions.PhoneNumber)
	case models.PaymentMethodUSDT:
		instructions.USDTWallet = strings.TrimSpace(h.cfg.USDTWallet)
		instructions.USDTNetwork = strings.TrimSpace(h.cfg.USDTNetwork)
		instructions.USDTMemo = strings.TrimSpace(h.cfg.USDTMemo)
		instructions.DisplayMessage = fmt.Sprintf("Send %s USDT to %s (%s).", amountText, instructions.USDTWallet, instructions.USDTNetwork)
	case models.PaymentMethodQR:
		payload := strings.TrimSpace(h.cfg.PaymentQRData)
		payload = strings.ReplaceAll(payload, "{order_id}", order.ID)
		payload = strings.ReplaceAll(payload, "{event_id}", strconv.FormatInt(order.EventID, 10))
		payload = strings.ReplaceAll(payload, "{amount_cents}", strconv.FormatInt(order.TotalCents, 10))
		payload = strings.ReplaceAll(payload, "{amount}", amountText)
		instructions.PaymentQRData = payload
		instructions.DisplayMessage = "Scan payment QR code and click I paid."
	default:
		instructions.DisplayMessage = "Follow payment instructions and click I paid."
	}
	return instructions
}

func (h *Handler) handleTicketingError(logger interface {
	Error(string, ...any)
	Warn(string, ...any)
}, w http.ResponseWriter, action string, err error) {
	switch {
	case errors.Is(err, repository.ErrOrderNotFound), errors.Is(err, repository.ErrTicketNotFound), errors.Is(err, pgx.ErrNoRows):
		logger.Warn(action, "status", "not_found", "error", err)
		writeError(w, http.StatusNotFound, "not found")
	case errors.Is(err, repository.ErrInvalidProduct), errors.Is(err, repository.ErrPromoInvalid), errors.Is(err, repository.ErrTicketQRMismatch):
		logger.Warn(action, "status", "invalid_request", "error", err)
		writeError(w, http.StatusBadRequest, err.Error())
	case errors.Is(err, repository.ErrOrderStateNotAllowed), errors.Is(err, repository.ErrTicketAlreadyRedeemed), errors.Is(err, repository.ErrInventoryLimitReached):
		logger.Warn(action, "status", "conflict", "error", err)
		writeError(w, http.StatusConflict, err.Error())
	default:
		logger.Error(action, "status", "internal_error", "error", err)
		writeError(w, http.StatusInternalServerError, "internal error")
	}
}

func mapSelections(items []orderSelectionRequest) []models.OrderProductSelection {
	out := make([]models.OrderProductSelection, 0, len(items))
	for _, item := range items {
		out = append(out, models.OrderProductSelection{
			ProductID: strings.TrimSpace(item.ProductID),
			Quantity:  item.Quantity,
		})
	}
	return out
}

func parseProductFilters(r *http.Request) (*int64, *bool, error) {
	var eventID *int64
	if raw := strings.TrimSpace(r.URL.Query().Get("event_id")); raw != "" {
		parsed, err := strconv.ParseInt(raw, 10, 64)
		if err != nil || parsed <= 0 {
			return nil, nil, errors.New("invalid event_id")
		}
		eventID = &parsed
	}
	var active *bool
	if raw := strings.TrimSpace(r.URL.Query().Get("active")); raw != "" {
		parsed, err := strconv.ParseBool(raw)
		if err != nil {
			return nil, nil, errors.New("invalid active")
		}
		active = &parsed
	}
	return eventID, active, nil
}

func parseIntQuery(r *http.Request, key string, fallback int) int {
	raw := strings.TrimSpace(r.URL.Query().Get(key))
	if raw == "" {
		return fallback
	}
	parsed, err := strconv.Atoi(raw)
	if err != nil {
		return fallback
	}
	return parsed
}

func formatAmount(cents int64) string {
	dollars := cents / 100
	rest := cents % 100
	if rest < 0 {
		rest = -rest
	}
	return fmt.Sprintf("%d.%02d", dollars, rest)
}
