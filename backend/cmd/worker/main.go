package main

import (
	"context"
	"fmt"
	"log"
	"time"

	"gigme/backend/internal/config"
	"gigme/backend/internal/db"
	"gigme/backend/internal/integrations"
	"gigme/backend/internal/models"
	"gigme/backend/internal/repository"
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

	log.Println("worker started")
	for {
		if err := repo.RequeueStaleProcessing(ctx, 10*time.Minute); err != nil {
			log.Printf("requeue stale jobs error: %v", err)
		}
		jobs, err := repo.FetchDueNotificationJobs(ctx, 100)
		if err != nil {
			log.Printf("fetch jobs error: %v", err)
			time.Sleep(5 * time.Second)
			continue
		}
		if len(jobs) == 0 {
			time.Sleep(10 * time.Second)
			continue
		}

		for _, job := range jobs {
			if err := handleJob(ctx, repo, telegram, cfg.BaseURL, job); err != nil {
				log.Printf("job %d failed: %v", job.ID, err)
			}
		}
	}
}

func handleJob(ctx context.Context, repo *repository.Repository, telegram *integrations.TelegramClient, baseURL string, job models.NotificationJob) error {
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

	return repo.UpdateNotificationJobStatus(ctx, job.ID, "sent", job.Attempts, "", nil)
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
	case "joined":
		return fmt.Sprintf("You joined the event: %s", title)
	case "reminder_60m":
		return fmt.Sprintf("Reminder: event starts in 60 minutes: %s", title)
	default:
		return ""
	}
}
