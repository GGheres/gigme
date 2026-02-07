package handlers

import (
	"context"
	"log/slog"
	"net/http"
	"time"

	"gigme/backend/internal/config"
	"gigme/backend/internal/eventparser"
	parsercore "gigme/backend/internal/eventparser/core"
	"gigme/backend/internal/geocode"
	authmw "gigme/backend/internal/http/middleware"
	"gigme/backend/internal/integrations"
	"gigme/backend/internal/rate"
	"gigme/backend/internal/repository"

	chimw "github.com/go-chi/chi/v5/middleware"
	"github.com/go-playground/validator/v10"
)

type Handler struct {
	repo             *repository.Repository
	s3               *integrations.S3Client
	telegram         *integrations.TelegramClient
	eventParser      *parsercore.Dispatcher
	geocoder         *geocode.Client
	cfg              *config.Config
	logger           *slog.Logger
	validator        *validator.Validate
	joinLeaveLimiter *rate.WindowLimiter
}

func New(repo *repository.Repository, s3 *integrations.S3Client, telegram *integrations.TelegramClient, cfg *config.Config, logger *slog.Logger) *Handler {
	if logger == nil {
		logger = slog.Default()
	}
	return &Handler{
		repo:             repo,
		s3:               s3,
		telegram:         telegram,
		eventParser:      eventparser.NewDispatcher(nil, logger, nil),
		geocoder:         geocode.NewClient(geocode.Config{}),
		cfg:              cfg,
		logger:           logger,
		validator:        validator.New(),
		joinLeaveLimiter: rate.NewWindowLimiter(10, time.Minute),
	}
}

func (h *Handler) withTimeout(ctx context.Context) (context.Context, context.CancelFunc) {
	return context.WithTimeout(ctx, 5*time.Second)
}

func (h *Handler) loggerForRequest(r *http.Request) *slog.Logger {
	logger := h.logger
	if logger == nil {
		return slog.Default()
	}
	if reqID := chimw.GetReqID(r.Context()); reqID != "" {
		logger = logger.With("request_id", reqID)
	}
	if userID, ok := authmw.UserIDFromContext(r.Context()); ok {
		logger = logger.With("user_id", userID)
	}
	if tgID, ok := authmw.TelegramIDFromContext(r.Context()); ok {
		logger = logger.With("telegram_id", tgID)
	}
	return logger
}
