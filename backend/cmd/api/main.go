package main

import (
	"context"
	"log"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"gigme/backend/internal/config"
	"gigme/backend/internal/db"
	"gigme/backend/internal/http/handlers"
	"gigme/backend/internal/http/middleware"
	"gigme/backend/internal/integrations"
	tochkaapi "gigme/backend/internal/integrations/tochka"
	"gigme/backend/internal/logging"
	"gigme/backend/internal/repository"

	"github.com/go-chi/chi/v5"
	chimw "github.com/go-chi/chi/v5/middleware"
)

func main() {
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
	logger = logger.With("service", "api")
	slog.SetDefault(logger)

	ctx := context.Background()
	pool, err := db.NewPool(ctx, cfg.DatabaseURL)
	if err != nil {
		logger.Error("db error", "error", err)
		os.Exit(1)
	}
	defer pool.Close()

	repo := repository.New(pool)
	telegram := integrations.NewTelegramClient(cfg.TelegramToken)
	var tochkaClient *tochkaapi.Client
	if cfg.Tochka.ClientID != "" && cfg.Tochka.ClientSecret != "" {
		tokenManager := tochkaapi.NewTokenManager(tochkaapi.TokenManagerConfig{
			ClientID:     cfg.Tochka.ClientID,
			ClientSecret: cfg.Tochka.ClientSecret,
			Scope:        cfg.Tochka.Scope,
			TokenURL:     cfg.Tochka.TokenURL,
		}, nil)
		tochkaClient = tochkaapi.NewClient(tochkaapi.Config{
			BaseURL:      cfg.Tochka.BaseURL,
			CustomerCode: cfg.Tochka.CustomerCode,
		}, tokenManager, nil, logger)
	}

	var s3Client *integrations.S3Client
	if cfg.S3.Bucket != "" {
		s3Client, err = integrations.NewS3(ctx, cfg.S3)
		if err != nil {
			logger.Error("s3 error", "error", err)
			os.Exit(1)
		}
	}

	h := handlers.New(repo, s3Client, telegram, tochkaClient, cfg, logger)

	r := chi.NewRouter()
	r.Use(chimw.RequestID)
	r.Use(chimw.RealIP)
	r.Use(middleware.RequestLogger(logger))
	r.Use(chimw.Recoverer)
	r.Use(chimw.Timeout(10 * time.Second))
	r.Use(corsMiddleware)

	r.Get("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	r.Get("/media/events/{id}/{index}", h.EventMedia)
	r.Get("/landing/events", h.LandingEvents)
	r.Get("/landing/content", h.LandingContent)

	r.Post("/auth/telegram", h.AuthTelegram)
	r.Post("/auth/admin", h.AuthAdmin)
	r.Get("/auth/standalone", h.StandaloneAuthPage)
	r.Post("/auth/standalone/exchange", h.StandaloneAuthExchange)
	r.Post("/telegram/webhook", h.TelegramWebhook)

	r.Group(func(r chi.Router) {
		r.Use(middleware.OptionalAuthMiddleware(cfg.JWTSecret))
		r.Post("/logs/client", h.ClientLogs)
	})

	r.Group(func(r chi.Router) {
		r.Use(middleware.AuthMiddleware(cfg.JWTSecret))
		r.Use(middleware.BlockedUserMiddleware(repo, cfg.AdminTGIDs))
		r.Get("/me", h.Me)
		r.Post("/me/location", h.UpdateLocation)
		r.Post("/me/push-token", h.UpsertPushToken)
		r.Get("/referrals/my-code", h.ReferralCode)
		r.Post("/referrals/claim", h.ClaimReferral)
		r.Post("/events", h.CreateEvent)
		r.Get("/events/mine", h.MyEvents)
		r.Get("/events/nearby", h.NearbyEvents)
		r.Get("/events/feed", h.Feed)
		r.Get("/events/{id}", h.GetEvent)
		r.Get("/events/{id}/products", h.ListEventProducts)
		r.Post("/events/{id}/join", h.JoinEvent)
		r.Post("/events/{id}/leave", h.LeaveEvent)
		r.Post("/events/{id}/like", h.LikeEvent)
		r.Delete("/events/{id}/like", h.UnlikeEvent)
		r.Get("/events/{id}/comments", h.ListEventComments)
		r.Post("/events/{id}/comments", h.AddEventComment)
		r.Post("/events/{id}/promote", h.PromoteEvent)
		r.Post("/media/presign", h.PresignMedia)
		r.Post("/media/upload", h.UploadMedia)
		r.Post("/wallet/topup/token", h.TopupToken)
		r.Post("/wallet/topup/card", h.TopupCard)
		r.Get("/payments/settings", h.GetPaymentSettings)
		r.Post("/orders", h.CreateOrder)
		r.Post("/payments/sbp/qr/create", h.CreateSBPQRCodePayment)
		r.Get("/payments/sbp/qr/{orderId}/status", h.GetSBPQRCodePaymentStatus)
		r.Get("/orders/my", h.ListMyOrders)
		r.Get("/tickets/my", h.ListMyTickets)
		r.Post("/promo-codes/validate", h.ValidatePromoCode)
		r.Post("/orders/{id}/confirm", h.ConfirmOrder)
		r.Post("/orders/{id}/cancel", h.CancelOrder)
		r.Post("/tickets/{id}/redeem", h.RedeemTicket)
		r.Get("/admin/users", h.ListAdminUsers)
		r.Get("/admin/users/{id}", h.GetAdminUser)
		r.Post("/admin/users/{id}/block", h.BlockUser)
		r.Post("/admin/users/{id}/unblock", h.UnblockUser)
		r.Post("/admin/broadcasts", h.CreateBroadcast)
		r.Post("/admin/broadcasts/{id}/start", h.StartBroadcast)
		r.Get("/admin/broadcasts", h.ListBroadcasts)
		r.Get("/admin/broadcasts/{id}", h.GetBroadcast)
		r.Get("/admin/parser/sources", h.ListParserSources)
		r.Post("/admin/parser/sources", h.CreateParserSource)
		r.Patch("/admin/parser/sources/{id}", h.UpdateParserSource)
		r.Post("/admin/parser/sources/{id}/parse", h.ParseParserSource)
		r.Post("/admin/parser/parse", h.ParseParserInput)
		r.Post("/admin/parser/geocode", h.GeocodeParserLocation)
		r.Get("/admin/parser/events", h.ListParsedEvents)
		r.Post("/admin/parser/events/{id}/import", h.ImportParsedEvent)
		r.Post("/admin/parser/events/{id}/reject", h.RejectParsedEvent)
		r.Delete("/admin/parser/events/{id}", h.DeleteParsedEvent)
		r.Post("/admin/events/{id}/hide", h.HideEvent)
		r.Post("/admin/events/{id}/landing", h.SetEventLandingPublished)
		r.Post("/admin/landing/content", h.UpsertLandingContent)
		r.Patch("/admin/events/{id}", h.UpdateEventAdmin)
		r.Delete("/admin/events/{id}", h.DeleteEventAdmin)
		r.Delete("/admin/comments/{id}", h.DeleteEventCommentAdmin)
		r.Get("/admin/orders", h.ListAdminOrders)
		r.Get("/admin/orders/{id}", h.GetAdminOrder)
		r.Post("/admin/orders/{orderId}/confirm", h.ConfirmOrder)
		r.Delete("/admin/orders/{id}", h.DeleteAdminOrder)
		r.Get("/admin/bot/messages", h.ListAdminBotMessages)
		r.Post("/admin/bot/messages/reply", h.ReplyAdminBotMessage)
		r.Post("/admin/tickets/redeem", h.AdminRedeemTicket)
		r.Get("/admin/stats", h.AdminStats)
		r.Get("/admin/payment-settings", h.GetAdminPaymentSettings)
		r.Post("/admin/payment-settings", h.UpsertAdminPaymentSettings)
		r.Get("/admin/products/tickets", h.ListAdminTicketProducts)
		r.Post("/admin/products/tickets", h.CreateAdminTicketProduct)
		r.Patch("/admin/products/tickets/{id}", h.PatchAdminTicketProduct)
		r.Delete("/admin/products/tickets/{id}", h.DeleteAdminTicketProduct)
		r.Get("/admin/products/transfers", h.ListAdminTransferProducts)
		r.Post("/admin/products/transfers", h.CreateAdminTransferProduct)
		r.Patch("/admin/products/transfers/{id}", h.PatchAdminTransferProduct)
		r.Delete("/admin/products/transfers/{id}", h.DeleteAdminTransferProduct)
		r.Get("/admin/promo-codes", h.ListAdminPromoCodes)
		r.Post("/admin/promo-codes", h.CreateAdminPromoCode)
		r.Patch("/admin/promo-codes/{id}", h.PatchAdminPromoCode)
		r.Delete("/admin/promo-codes/{id}", h.DeleteAdminPromoCode)
	})

	srv := &http.Server{
		Addr:    cfg.HTTPAddr,
		Handler: r,
	}

	go func() {
		logger.Info("api_listening", "addr", cfg.HTTPAddr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Error("server error", "error", err)
			os.Exit(1)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop

	logger.Info("shutdown", "service", "api")
	ctxShutdown, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = srv.Shutdown(ctxShutdown)
}

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET,POST,PATCH,DELETE,OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Authorization,Content-Type,Ngrok-Skip-Browser-Warning")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}
