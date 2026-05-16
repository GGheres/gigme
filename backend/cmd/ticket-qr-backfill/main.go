package main

import (
	"context"
	"flag"
	"log"
	"log/slog"
	"os"
	"strings"
	"time"

	"gigme/backend/internal/config"
	"gigme/backend/internal/db"
	"gigme/backend/internal/integrations"
	"gigme/backend/internal/logging"
	"gigme/backend/internal/models"
	"gigme/backend/internal/repository"
	"gigme/backend/internal/ticketdelivery"
)

// main runs the ticket QR backfill command.
func main() {
	limit := flag.Int("limit", 500, "maximum number of orders to process")
	dryRun := flag.Bool("dry-run", false, "list orders without sending QR codes")
	flag.Parse()

	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config error: %v", err)
	}
	logger, cleanup, err := logging.New(cfg.Logging)
	if err != nil {
		log.Fatalf("log error: %v", err)
	}
	defer func() {
		_ = cleanup()
	}()
	logger = logger.With("service", "ticket-qr-backfill")
	slog.SetDefault(logger)

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()

	pool, err := db.NewPool(ctx, cfg.DatabaseURL)
	if err != nil {
		logger.Error("db_error", "error", err)
		os.Exit(1)
	}
	defer pool.Close()

	repo := repository.New(pool)
	orderIDs, err := repo.ListOrdersNeedingQRDelivery(ctx, *limit)
	if err != nil {
		logger.Error("list_orders_error", "error", err)
		os.Exit(1)
	}
	logger.Info("orders_found", "count", len(orderIDs), "dry_run", *dryRun)
	if *dryRun {
		for _, orderID := range orderIDs {
			logger.Info("order_needs_qr_delivery", "order_id", orderID)
		}
		return
	}

	telegram := integrations.NewTelegramClient(cfg.TelegramToken)
	sent := 0
	failed := 0
	for _, orderID := range orderIDs {
		detail, telegramID, _, err := repo.ConfirmOrder(ctx, orderID, 0, cfg.HMACSecret)
		if err != nil {
			failed++
			logger.Warn("confirm_order_failed", "order_id", orderID, "error", err)
			continue
		}
		if telegramID <= 0 {
			failed++
			logger.Warn("order_without_telegram_id", "order_id", orderID)
			continue
		}
		orderSent, orderFailed := deliverOrderQRCodes(ctx, repo, telegram, telegramID, detail, logger)
		sent += orderSent
		failed += orderFailed
	}
	logger.Info("backfill_finished", "orders", len(orderIDs), "sent", sent, "failed", failed)
}

// deliverOrderQRCodes sends all pending QR codes for a confirmed order.
func deliverOrderQRCodes(
	ctx context.Context,
	repo *repository.Repository,
	telegram *integrations.TelegramClient,
	telegramID int64,
	detail models.OrderDetail,
	logger *slog.Logger,
) (int, int) {
	sent := 0
	failed := 0
	for _, ticket := range detail.Tickets {
		if strings.TrimSpace(ticket.QRPayload) == "" || ticket.QRDeliveredAt != nil {
			continue
		}
		if err := ticketdelivery.SendTicketQR(telegram, telegramID, ticket); err != nil {
			failed++
			_ = repo.MarkTicketQRDeliveryFailed(ctx, ticket.ID, err.Error())
			logger.Warn("ticket_delivery_failed", "order_id", detail.Order.ID, "ticket_id", ticket.ID, "telegram_id", telegramID, "error", err)
			continue
		}
		if err := repo.MarkTicketQRDelivered(ctx, ticket.ID); err != nil {
			failed++
			logger.Warn("ticket_delivery_mark_failed", "order_id", detail.Order.ID, "ticket_id", ticket.ID, "telegram_id", telegramID, "error", err)
			continue
		}
		sent++
		logger.Info("ticket_delivered", "order_id", detail.Order.ID, "ticket_id", ticket.ID, "telegram_id", telegramID, "ticket_type", ticket.TicketType)
	}
	return sent, failed
}
