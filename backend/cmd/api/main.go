package main

import (
	"context"
	"log"
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
	"gigme/backend/internal/repository"

	"github.com/go-chi/chi/v5"
	chimw "github.com/go-chi/chi/v5/middleware"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config error: %v", err)
	}

	ctx := context.Background()
	pool, err := db.NewPool(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("db error: %v", err)
	}
	defer pool.Close()

	repo := repository.New(pool)
	telegram := integrations.NewTelegramClient(cfg.TelegramToken)

	var s3Client *integrations.S3Client
	if cfg.S3.Bucket != "" {
		s3Client, err = integrations.NewS3(ctx, cfg.S3)
		if err != nil {
			log.Fatalf("s3 error: %v", err)
		}
	}

	h := handlers.New(repo, s3Client, telegram, cfg)

	r := chi.NewRouter()
	r.Use(chimw.RequestID)
	r.Use(chimw.RealIP)
	r.Use(chimw.Recoverer)
	r.Use(chimw.Timeout(10 * time.Second))
	r.Use(corsMiddleware)

	r.Get("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	r.Post("/auth/telegram", h.AuthTelegram)

	r.Group(func(r chi.Router) {
		r.Use(middleware.AuthMiddleware(cfg.JWTSecret))
		r.Get("/me", h.Me)
		r.Post("/events", h.CreateEvent)
		r.Get("/events/nearby", h.NearbyEvents)
		r.Get("/events/feed", h.Feed)
		r.Get("/events/{id}", h.GetEvent)
		r.Post("/events/{id}/join", h.JoinEvent)
		r.Post("/events/{id}/leave", h.LeaveEvent)
		r.Post("/events/{id}/promote", h.PromoteEvent)
		r.Post("/media/presign", h.PresignMedia)
		r.Post("/admin/events/{id}/hide", h.HideEvent)
	})

	srv := &http.Server{
		Addr:    cfg.HTTPAddr,
		Handler: r,
	}

	go func() {
		log.Printf("api listening on %s", cfg.HTTPAddr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("server error: %v", err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop

	ctxShutdown, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = srv.Shutdown(ctxShutdown)
}

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET,POST,OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Authorization,Content-Type")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}
