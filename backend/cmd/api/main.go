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

	var s3Client *integrations.S3Client
	if cfg.S3.Bucket != "" {
		s3Client, err = integrations.NewS3(ctx, cfg.S3)
		if err != nil {
			logger.Error("s3 error", "error", err)
			os.Exit(1)
		}
	}

	h := handlers.New(repo, s3Client, telegram, cfg, logger)

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

	r.Post("/auth/telegram", h.AuthTelegram)
	r.Post("/telegram/webhook", h.TelegramWebhook)

	r.Group(func(r chi.Router) {
		r.Use(middleware.OptionalAuthMiddleware(cfg.JWTSecret))
		r.Post("/logs/client", h.ClientLogs)
	})

	r.Group(func(r chi.Router) {
		r.Use(middleware.AuthMiddleware(cfg.JWTSecret))
		r.Get("/me", h.Me)
		r.Post("/me/location", h.UpdateLocation)
		r.Post("/events", h.CreateEvent)
		r.Get("/events/mine", h.MyEvents)
		r.Get("/events/nearby", h.NearbyEvents)
		r.Get("/events/feed", h.Feed)
		r.Get("/events/{id}", h.GetEvent)
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
		r.Post("/admin/events/{id}/hide", h.HideEvent)
		r.Patch("/admin/events/{id}", h.UpdateEventAdmin)
		r.Delete("/admin/events/{id}", h.DeleteEventAdmin)
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
