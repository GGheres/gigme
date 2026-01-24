package main

import (
	"context"
	"fmt"
	"log"
	"log/slog"
	"os"
	"time"

	"gigme/backend/internal/config"
	"gigme/backend/internal/db"
	"gigme/backend/internal/integrations"
	"gigme/backend/internal/logging"
	"gigme/backend/internal/models"
	"gigme/backend/internal/repository"
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
	logger = logger.With("service", "worker")
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

	logger.Info("worker_started")
	for {
		if err := repo.RequeueStaleProcessing(ctx, 10*time.Minute); err != nil {
			logger.Warn("requeue_stale_jobs_error", "error", err)
		}
		jobs, err := repo.FetchDueNotificationJobs(ctx, 100)
		if err != nil {
			logger.Error("fetch_jobs_error", "error", err)
			time.Sleep(5 * time.Second)
			continue
		}
		if len(jobs) == 0 {
			time.Sleep(10 * time.Second)
			continue
		}

		for _, job := range jobs {
			if err := handleJob(ctx, repo, telegram, cfg.BaseURL, job, logger); err != nil {
				logger.Error("job_failed", "job_id", job.ID, "error", err)
			}
		}
	}
}

func handleJob(ctx context.Context, repo *repository.Repository, telegram *integrations.TelegramClient, baseURL string, job models.NotificationJob, logger *slog.Logger) error {
	if logger == nil {
		logger = slog.Default()
	}
	logger.Info("job_processing", "job_id", job.ID, "kind", job.Kind, "user_id", job.UserID, "event_id", job.EventID, "run_at", job.RunAt)
	chatID, err := repo.GetUserTelegramID(ctx, job.UserID)
	if err != nil {
		return repo.UpdateNotificationJobStatus(ctx, job.ID, "failed", job.Attempts+1, err.Error(), nil)
	}

	text := buildMessage(job, baseURL)
	if text == "" {
		return repo.UpdateNotificationJobStatus(ctx, job.ID, "failed", job.Attempts+1, "unknown job kind", nil)
	}

	if err := telegram.SendMessage(chatID, text); err != nil {
		attempts := job.Attempts + 1
		if attempts >= 3 {
			return repo.UpdateNotificationJobStatus(ctx, job.ID, "failed", attempts, err.Error(), nil)
		}
		delay := time.Duration(1<<attempts) * time.Minute
		nextRun := time.Now().Add(delay)
		return repo.UpdateNotificationJobStatus(ctx, job.ID, "pending", attempts, err.Error(), &nextRun)
	}

	if err := repo.UpdateNotificationJobStatus(ctx, job.ID, "sent", job.Attempts, "", nil); err != nil {
		return err
	}
	logger.Info("job_sent", "job_id", job.ID, "kind", job.Kind, "user_id", job.UserID)
	return nil
}

func buildMessage(job models.NotificationJob, baseURL string) string {
	title := ""
	if job.Payload != nil {
		if v, ok := job.Payload["title"].(string); ok {
			title = v
		}
	}

	switch job.Kind {
	case "event_created":
		return fmt.Sprintf("Event created: %s", title)
	case "event_nearby":
		return fmt.Sprintf("New event nearby: %s", title)
	case "joined":
		return fmt.Sprintf("You joined the event: %s", title)
	case "reminder_60m":
		return fmt.Sprintf("Reminder: event starts in 60 minutes: %s", title)
	default:
		return ""
	}
}
