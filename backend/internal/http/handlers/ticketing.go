package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"gigme/backend/internal/http/middleware"
	tochkaapi "gigme/backend/internal/integrations/tochka"
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

type adminRedeemTicketRequest struct {
	TicketID  string `json:"ticketId"`
	QRPayload string `json:"qrPayload"`
}

type createSbpQRCodeRequest struct {
	EventID       int64                   `json:"eventId"`
	TicketItems   []orderSelectionRequest `json:"ticketItems"`
	TransferItems []orderSelectionRequest `json:"transferItems"`
	PromoCode     string                  `json:"promoCode"`
	RedirectURL   string                  `json:"redirectUrl"`
}

type upsertPaymentSettingsRequest struct {
	PhoneNumber      *string `json:"phoneNumber"`
	USDTWallet       *string `json:"usdtWallet"`
	USDTNetwork      *string `json:"usdtNetwork"`
	USDTMemo         *string `json:"usdtMemo"`
	PhoneDescription *string `json:"phoneDescription"`
	USDTDescription  *string `json:"usdtDescription"`
	QRDescription    *string `json:"qrDescription"`
	SBPDescription   *string `json:"sbpDescription"`
}

type createSbpQRCodeResponse struct {
	Order models.OrderDetail `json:"order"`
	SBPQR models.SbpQR       `json:"sbpQr"`
}

type sbpQRStatusResponse struct {
	OrderID       string              `json:"orderId"`
	QRCID         string              `json:"qrcId"`
	PaymentStatus string              `json:"paymentStatus"`
	OrderStatus   string              `json:"orderStatus"`
	Paid          bool                `json:"paid"`
	Unknown       bool                `json:"unknown"`
	Message       string              `json:"message,omitempty"`
	Detail        *models.OrderDetail `json:"detail,omitempty"`
}

const paymentProviderTochkaSBP = "tochka_sbp"

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
	paymentSettings := h.loadPaymentSettings(ctx)
	detail.PaymentInstructions = h.buildPaymentInstructions(detail.Order, paymentSettings)
	writeJSON(w, http.StatusCreated, detail)
}

func (h *Handler) CreateSBPQRCodePayment(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	userID, ok := middleware.UserIDFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	if !h.hasTochkaSBPConfig() {
		writeError(w, http.StatusServiceUnavailable, "sbp payment is not configured")
		return
	}

	var req createSbpQRCodeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		logger.Warn("create_sbp_qr", "status", "invalid_json")
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()

	detail, err := h.repo.CreateOrder(ctx, models.CreateOrderParams{
		UserID:           userID,
		EventID:          req.EventID,
		PaymentMethod:    models.PaymentMethodTochkaSBPQR,
		PaymentReference: "",
		TicketItems:      mapSelections(req.TicketItems),
		TransferItems:    mapSelections(req.TransferItems),
		PromoCode:        strings.TrimSpace(req.PromoCode),
	})
	if err != nil {
		h.handleTicketingError(logger, w, "create_sbp_qr", err)
		return
	}

	amount := detail.Order.TotalCents
	if amount <= 0 {
		writeError(w, http.StatusBadRequest, "order amount must be greater than zero for sbp payment")
		return
	}

	paymentPurpose := fmt.Sprintf("Order %s Event %d", detail.Order.ID, detail.Order.EventID)
	ttl := 15
	registerReq := tochkaapi.RegisterQRCodeRequest{
		Amount:         &amount,
		Currency:       "RUB",
		PaymentPurpose: paymentPurpose,
		QRCType:        tochkaapi.QRCTypeDynamic,
		TTL:            &ttl,
		RedirectURL:    h.resolveSBPRedirectURL(strings.TrimSpace(req.RedirectURL), detail.Order.ID),
	}

	registered, raw, err := h.tochka.RegisterQRCode(ctx, h.cfg.Tochka.MerchantID, h.cfg.Tochka.AccountID, registerReq)
	if err != nil {
		logger.Error("create_sbp_qr", "status", "tochka_error", "order_id", detail.Order.ID, "error", err)
		writeJSON(w, http.StatusBadGateway, map[string]interface{}{
			"error": "tochka register qr failed",
			"order": detail,
		})
		return
	}

	sbpQR, err := h.repo.UpsertSbpQR(
		ctx,
		detail.Order.ID,
		registered.QRCID,
		registered.Payload,
		h.cfg.Tochka.MerchantID,
		h.cfg.Tochka.AccountID,
		"REGISTERED",
	)
	if err != nil {
		logger.Error("create_sbp_qr", "status", "db_error", "order_id", detail.Order.ID, "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}

	if _, err := h.repo.UpsertPayment(ctx, repository.UpsertPaymentParams{
		OrderID:           detail.Order.ID,
		Provider:          paymentProviderTochkaSBP,
		ProviderPaymentID: registered.QRCID,
		Amount:            detail.Order.TotalCents,
		Status:            "REGISTERED",
		RawResponseJSON:   raw,
	}); err != nil {
		logger.Warn("create_sbp_qr", "status", "payment_upsert_failed", "order_id", detail.Order.ID, "error", err)
	}

	paymentSettings := h.loadPaymentSettings(ctx)
	detail.PaymentInstructions = h.buildPaymentInstructions(detail.Order, paymentSettings)
	h.attachSBPInstructions(&detail, &sbpQR)
	writeJSON(w, http.StatusCreated, createSbpQRCodeResponse{
		Order: detail,
		SBPQR: sbpQR,
	})
}

func (h *Handler) GetSBPQRCodePaymentStatus(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	userID, ok := middleware.UserIDFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	orderID := strings.TrimSpace(chi.URLParam(r, "orderId"))
	if orderID == "" {
		writeError(w, http.StatusBadRequest, "invalid order id")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()

	detail, err := h.repo.GetOrderDetail(ctx, orderID, false)
	if err != nil {
		h.handleTicketingError(logger, w, "sbp_status", err)
		return
	}

	isAdmin := false
	if tgID, ok := middleware.TelegramIDFromContext(r.Context()); ok {
		_, isAdmin = h.cfg.AdminTGIDs[tgID]
	}
	if detail.Order.UserID != userID && !isAdmin {
		writeError(w, http.StatusForbidden, "forbidden")
		return
	}

	sbpQR, err := h.repo.GetSbpQRByOrderID(ctx, orderID)
	if err != nil {
		h.handleTicketingError(logger, w, "sbp_status", err)
		return
	}

	response := sbpQRStatusResponse{
		OrderID:     orderID,
		QRCID:       sbpQR.QRCID,
		OrderStatus: strings.ToUpper(strings.TrimSpace(detail.Order.Status)),
	}
	paymentSettings := h.loadPaymentSettings(ctx)

	if isPaidOrderStatus(detail.Order.Status) || isRedeemedOrderStatus(detail.Order.Status) {
		response.PaymentStatus = "Accepted"
		response.Paid = true
		detail.PaymentInstructions = h.buildPaymentInstructions(detail.Order, paymentSettings)
		h.attachSBPInstructions(&detail, &sbpQR)
		response.Detail = &detail
		writeJSON(w, http.StatusOK, response)
		return
	}

	if !h.hasTochkaSBPConfig() || h.tochka == nil {
		response.Unknown = true
		response.Message = "tochka configuration is missing"
		response.PaymentStatus = strings.TrimSpace(sbpQR.Status)
		writeJSON(w, http.StatusOK, response)
		return
	}

	statuses, raw, err := h.tochka.GetQRCodesPaymentStatus(ctx, []string{sbpQR.QRCID})
	if err != nil {
		response.Unknown = true
		response.Message = "failed to fetch payment status"
		response.PaymentStatus = strings.TrimSpace(sbpQR.Status)
		logger.Warn("sbp_status", "status", "tochka_error", "order_id", orderID, "qrc_id", sbpQR.QRCID, "error", err)
		writeJSON(w, http.StatusOK, response)
		return
	}

	paymentStatus := strings.TrimSpace(sbpQR.Status)
	var providerPaymentID string
	if len(statuses) > 0 {
		paymentStatus = strings.TrimSpace(statuses[0].Status)
		if paymentStatus == "" {
			paymentStatus = strings.TrimSpace(statuses[0].Code)
		}
		if strings.TrimSpace(statuses[0].Message) != "" {
			response.Message = strings.TrimSpace(statuses[0].Message)
		}
		providerPaymentID = strings.TrimSpace(statuses[0].TrxID)
	}
	response.PaymentStatus = paymentStatus

	if err := h.repo.UpdateSbpQRStatus(ctx, orderID, paymentStatus); err != nil {
		logger.Warn("sbp_status", "status", "sbp_qr_update_failed", "order_id", orderID, "error", err)
	}
	if _, err := h.repo.UpsertPayment(ctx, repository.UpsertPaymentParams{
		OrderID:           orderID,
		Provider:          paymentProviderTochkaSBP,
		ProviderPaymentID: providerPaymentID,
		Amount:            detail.Order.TotalCents,
		Status:            normalizeProviderStatus(paymentStatus),
		RawResponseJSON:   raw,
	}); err != nil {
		logger.Warn("sbp_status", "status", "payment_upsert_failed", "order_id", orderID, "error", err)
	}

	if tochkaapi.IsPaidStatus(paymentStatus) {
		confirmedDetail, telegramID, confirmedNow, err := h.repo.ConfirmOrder(ctx, orderID, 0, h.cfg.HMACSecret)
		if err != nil {
			h.handleTicketingError(logger, w, "sbp_status_confirm", err)
			return
		}
		confirmedDetail.PaymentInstructions = h.buildPaymentInstructions(confirmedDetail.Order, paymentSettings)
		h.attachSBPInstructions(&confirmedDetail, &sbpQR)
		response.OrderStatus = confirmedDetail.Order.Status
		response.Paid = true
		response.Detail = &confirmedDetail

		if confirmedNow && telegramID > 0 {
			for _, ticket := range confirmedDetail.Tickets {
				if strings.TrimSpace(ticket.QRPayload) == "" {
					continue
				}
				if err := h.sendTicketQrToBot(telegramID, ticket); err != nil {
					logger.Warn("sbp_status_confirm", "status", "ticket_delivery_failed", "ticket_id", ticket.ID, "telegram_id", telegramID, "error", err)
				}
			}
		}

		writeJSON(w, http.StatusOK, response)
		return
	}

	response.Paid = false
	response.Unknown = paymentStatus == ""
	writeJSON(w, http.StatusOK, response)
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
		orderID = strings.TrimSpace(chi.URLParam(r, "orderId"))
	}
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
	paymentSettings := h.loadPaymentSettings(ctx)
	detail.PaymentInstructions = h.buildPaymentInstructions(detail.Order, paymentSettings)
	if sbpQR, err := h.repo.GetSbpQRByOrderID(ctx, orderID); err == nil {
		h.attachSBPInstructions(&detail, &sbpQR)
	}
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
	detail, telegramID, confirmedNow, err := h.repo.ConfirmOrder(ctx, orderID, adminID, h.cfg.HMACSecret)
	if err != nil {
		h.handleTicketingError(logger, w, "admin_confirm_order", err)
		return
	}
	paymentSettings := h.loadPaymentSettings(ctx)
	detail.PaymentInstructions = h.buildPaymentInstructions(detail.Order, paymentSettings)
	if sbpQR, err := h.repo.GetSbpQRByOrderID(ctx, orderID); err == nil {
		h.attachSBPInstructions(&detail, &sbpQR)
	}

	if confirmedNow && telegramID > 0 {
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
	paymentSettings := h.loadPaymentSettings(ctx)
	detail.PaymentInstructions = h.buildPaymentInstructions(detail.Order, paymentSettings)
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

func (h *Handler) AdminRedeemTicket(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_redeem_ticket"); !ok {
		return
	}
	adminID, ok := middleware.UserIDFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	var req adminRedeemTicketRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}

	qrPayload := strings.TrimSpace(req.QRPayload)
	ticketID := strings.TrimSpace(req.TicketID)
	if qrPayload != "" {
		claims, err := ticketing.VerifyQRPayload(h.cfg.HMACSecret, qrPayload)
		if err != nil {
			writeError(w, http.StatusBadRequest, "invalid qrPayload")
			return
		}
		ticketID = claims.TicketID
	}
	if ticketID == "" {
		writeError(w, http.StatusBadRequest, "ticketId or valid qrPayload is required")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	result, err := h.repo.RedeemTicket(ctx, ticketID, adminID, qrPayload, h.cfg.HMACSecret)
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

func (h *Handler) GetPaymentSettings(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	writeJSON(w, http.StatusOK, h.loadPaymentSettings(ctx))
}

func (h *Handler) GetAdminPaymentSettings(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_get_payment_settings"); !ok {
		return
	}
	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	writeJSON(w, http.StatusOK, h.loadPaymentSettings(ctx))
}

func (h *Handler) UpsertAdminPaymentSettings(w http.ResponseWriter, r *http.Request) {
	logger := h.loggerForRequest(r)
	if _, ok := h.requireAdmin(logger, w, r, "admin_upsert_payment_settings"); !ok {
		return
	}
	adminID, ok := middleware.UserIDFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	var req upsertPaymentSettingsRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return
	}
	if !req.hasAny() {
		writeError(w, http.StatusBadRequest, "at least one field is required")
		return
	}

	ctx, cancel := h.withTimeout(r.Context())
	defer cancel()
	current := h.loadPaymentSettings(ctx)
	merged := mergePaymentSettings(current, req)
	merged.UpdatedBy = &adminID

	saved, err := h.repo.UpsertPaymentSettings(ctx, merged)
	if err != nil {
		logger.Error("admin_upsert_payment_settings", "status", "db_error", "error", err)
		writeError(w, http.StatusInternalServerError, "db error")
		return
	}
	writeJSON(w, http.StatusOK, saved)
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
	caption := fmt.Sprintf("Ticket %s\nEvent: %d\nType: %s\nQty: %d", ticket.ID, ticket.EventID, ticket.TicketType, ticket.Quantity)
	if err := h.telegram.SendPhotoBytes(userTelegramID, fmt.Sprintf("ticket-%s.png", ticket.ID), qrBytes, caption, nil); err != nil {
		return h.telegram.SendMessage(userTelegramID, fmt.Sprintf("Ticket %s\nQR payload: %s", ticket.ID, payload))
	}
	return nil
}

func (h *Handler) buildPaymentInstructions(order models.Order, paymentSettings models.PaymentSettings) models.PaymentInstructions {
	amountText := formatAmount(order.TotalCents)
	instructions := models.PaymentInstructions{
		AmountCents: order.TotalCents,
		Currency:    order.Currency,
	}
	switch order.PaymentMethod {
	case models.PaymentMethodPhone:
		instructions.PhoneNumber = strings.TrimSpace(paymentSettings.PhoneNumber)
		instructions.DisplayMessage = applyPaymentTextTemplate(
			paymentSettings.PhoneDescription,
			order,
			amountText,
			fmt.Sprintf("Transfer %s to phone number %s and click I paid.", amountText, instructions.PhoneNumber),
		)
	case models.PaymentMethodUSDT:
		instructions.USDTWallet = strings.TrimSpace(paymentSettings.USDTWallet)
		instructions.USDTNetwork = strings.TrimSpace(paymentSettings.USDTNetwork)
		instructions.USDTMemo = strings.TrimSpace(paymentSettings.USDTMemo)
		instructions.DisplayMessage = applyPaymentTextTemplate(
			paymentSettings.USDTDescription,
			order,
			amountText,
			fmt.Sprintf("Send %s USDT to %s (%s).", amountText, instructions.USDTWallet, instructions.USDTNetwork),
		)
	case models.PaymentMethodQR:
		payload := strings.TrimSpace(h.cfg.PaymentQRData)
		payload = strings.ReplaceAll(payload, "{order_id}", order.ID)
		payload = strings.ReplaceAll(payload, "{event_id}", strconv.FormatInt(order.EventID, 10))
		payload = strings.ReplaceAll(payload, "{amount_cents}", strconv.FormatInt(order.TotalCents, 10))
		payload = strings.ReplaceAll(payload, "{amount}", amountText)
		instructions.PaymentQRData = payload
		instructions.DisplayMessage = applyPaymentTextTemplate(
			paymentSettings.QRDescription,
			order,
			amountText,
			"Scan payment QR code and click I paid.",
		)
	case models.PaymentMethodTochkaSBPQR:
		instructions.DisplayMessage = applyPaymentTextTemplate(
			paymentSettings.SBPDescription,
			order,
			amountText,
			"Scan SBP QR and complete payment in your bank app.",
		)
	default:
		instructions.DisplayMessage = "Follow payment instructions and click I paid."
	}
	return instructions
}

func (h *Handler) loadPaymentSettings(ctx context.Context) models.PaymentSettings {
	settings := models.PaymentSettings{
		PhoneNumber: strings.TrimSpace(h.cfg.PhoneNumber),
		USDTWallet:  strings.TrimSpace(h.cfg.USDTWallet),
		USDTNetwork: strings.TrimSpace(h.cfg.USDTNetwork),
		USDTMemo:    strings.TrimSpace(h.cfg.USDTMemo),
	}
	if strings.TrimSpace(settings.USDTNetwork) == "" {
		settings.USDTNetwork = "TRC20"
	}
	stored, err := h.repo.GetPaymentSettings(ctx)
	if err != nil {
		return settings
	}
	if stored.UpdatedBy != nil {
		if strings.TrimSpace(stored.USDTNetwork) == "" {
			stored.USDTNetwork = "TRC20"
		}
		return stored
	}

	if strings.TrimSpace(stored.PhoneNumber) != "" {
		settings.PhoneNumber = strings.TrimSpace(stored.PhoneNumber)
	}
	if strings.TrimSpace(stored.USDTWallet) != "" {
		settings.USDTWallet = strings.TrimSpace(stored.USDTWallet)
	}
	if strings.TrimSpace(stored.USDTNetwork) != "" {
		settings.USDTNetwork = strings.TrimSpace(stored.USDTNetwork)
	}
	if strings.TrimSpace(stored.USDTMemo) != "" {
		settings.USDTMemo = strings.TrimSpace(stored.USDTMemo)
	}
	settings.PhoneDescription = strings.TrimSpace(stored.PhoneDescription)
	settings.USDTDescription = strings.TrimSpace(stored.USDTDescription)
	settings.QRDescription = strings.TrimSpace(stored.QRDescription)
	settings.SBPDescription = strings.TrimSpace(stored.SBPDescription)
	settings.UpdatedBy = stored.UpdatedBy
	settings.CreatedAt = stored.CreatedAt
	settings.UpdatedAt = stored.UpdatedAt
	return settings
}

func mergePaymentSettings(current models.PaymentSettings, req upsertPaymentSettingsRequest) models.PaymentSettings {
	merged := current
	if req.PhoneNumber != nil {
		merged.PhoneNumber = strings.TrimSpace(*req.PhoneNumber)
	}
	if req.USDTWallet != nil {
		merged.USDTWallet = strings.TrimSpace(*req.USDTWallet)
	}
	if req.USDTNetwork != nil {
		merged.USDTNetwork = strings.TrimSpace(*req.USDTNetwork)
	}
	if req.USDTMemo != nil {
		merged.USDTMemo = strings.TrimSpace(*req.USDTMemo)
	}
	if req.PhoneDescription != nil {
		merged.PhoneDescription = strings.TrimSpace(*req.PhoneDescription)
	}
	if req.USDTDescription != nil {
		merged.USDTDescription = strings.TrimSpace(*req.USDTDescription)
	}
	if req.QRDescription != nil {
		merged.QRDescription = strings.TrimSpace(*req.QRDescription)
	}
	if req.SBPDescription != nil {
		merged.SBPDescription = strings.TrimSpace(*req.SBPDescription)
	}
	if strings.TrimSpace(merged.USDTNetwork) == "" {
		merged.USDTNetwork = "TRC20"
	}
	return merged
}

func (r upsertPaymentSettingsRequest) hasAny() bool {
	return r.PhoneNumber != nil ||
		r.USDTWallet != nil ||
		r.USDTNetwork != nil ||
		r.USDTMemo != nil ||
		r.PhoneDescription != nil ||
		r.USDTDescription != nil ||
		r.QRDescription != nil ||
		r.SBPDescription != nil
}

func applyPaymentTextTemplate(template string, order models.Order, amountText string, fallback string) string {
	out := strings.TrimSpace(template)
	if out == "" {
		return fallback
	}
	out = strings.ReplaceAll(out, "{order_id}", strings.TrimSpace(order.ID))
	out = strings.ReplaceAll(out, "{event_id}", strconv.FormatInt(order.EventID, 10))
	out = strings.ReplaceAll(out, "{amount_cents}", strconv.FormatInt(order.TotalCents, 10))
	out = strings.ReplaceAll(out, "{amount}", amountText)
	return out
}

func (h *Handler) handleTicketingError(logger interface {
	Error(string, ...any)
	Warn(string, ...any)
}, w http.ResponseWriter, action string, err error) {
	switch {
	case errors.Is(err, repository.ErrOrderNotFound), errors.Is(err, repository.ErrTicketNotFound), errors.Is(err, repository.ErrSbpQRNotFound), errors.Is(err, pgx.ErrNoRows):
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

func (h *Handler) hasTochkaSBPConfig() bool {
	return h.tochka != nil &&
		strings.TrimSpace(h.cfg.Tochka.MerchantID) != "" &&
		strings.TrimSpace(h.cfg.Tochka.AccountID) != ""
}

func (h *Handler) resolveSBPRedirectURL(requestURL, orderID string) string {
	redirectURL := strings.TrimSpace(requestURL)
	if redirectURL == "" {
		redirectURL = strings.TrimSpace(h.cfg.Tochka.RedirectURL)
	}
	if redirectURL == "" {
		return ""
	}
	redirectURL = strings.ReplaceAll(redirectURL, "{order_id}", strings.TrimSpace(orderID))
	redirectURL = strings.ReplaceAll(redirectURL, "{orderId}", strings.TrimSpace(orderID))
	return redirectURL
}

func (h *Handler) attachSBPInstructions(detail *models.OrderDetail, sbpQR *models.SbpQR) {
	if detail == nil || sbpQR == nil {
		return
	}
	detail.PaymentInstructions.PaymentQRCID = strings.TrimSpace(sbpQR.QRCID)
	detail.PaymentInstructions.PaymentQRData = strings.TrimSpace(sbpQR.Payload)
	if detail.PaymentInstructions.DisplayMessage == "" {
		detail.PaymentInstructions.DisplayMessage = "Scan SBP QR and complete payment in your bank app."
	}
}

func normalizeProviderStatus(status string) string {
	switch strings.ToUpper(strings.TrimSpace(status)) {
	case "ACCEPTED":
		return "PAID"
	case "REJECTED":
		return "FAILED"
	case "NOTSTARTED", "RECEIVED", "INPROGRESS":
		return "PENDING"
	default:
		return "UNKNOWN"
	}
}

func isPaidOrderStatus(status string) bool {
	switch strings.ToUpper(strings.TrimSpace(status)) {
	case "PAID", "CONFIRMED":
		return true
	default:
		return false
	}
}

func isRedeemedOrderStatus(status string) bool {
	return strings.EqualFold(strings.TrimSpace(status), models.OrderStatusRedeemed)
}
