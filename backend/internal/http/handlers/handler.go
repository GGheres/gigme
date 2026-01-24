package handlers

import (
	"context"
	"time"

	"gigme/backend/internal/config"
	"gigme/backend/internal/integrations"
	"gigme/backend/internal/rate"
	"gigme/backend/internal/repository"

	"github.com/go-playground/validator/v10"
)

type Handler struct {
	repo             *repository.Repository
	s3               *integrations.S3Client
	telegram         *integrations.TelegramClient
	cfg              *config.Config
	validator        *validator.Validate
	joinLeaveLimiter *rate.WindowLimiter
}

func New(repo *repository.Repository, s3 *integrations.S3Client, telegram *integrations.TelegramClient, cfg *config.Config) *Handler {
	return &Handler{
		repo:             repo,
		s3:               s3,
		telegram:         telegram,
		cfg:              cfg,
		validator:        validator.New(),
		joinLeaveLimiter: rate.NewWindowLimiter(10, time.Minute),
	}
}

func (h *Handler) withTimeout(ctx context.Context) (context.Context, context.CancelFunc) {
	return context.WithTimeout(ctx, 5*time.Second)
}
