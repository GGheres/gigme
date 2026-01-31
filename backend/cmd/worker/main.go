package main

import (
	"context"
	"fmt"
	"log"
	"log/slog"
	"net/url"
	"os"
	"path"
	"strconv"
	"strings"
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
			if err := handleJob(ctx, repo, telegram, cfg.BaseURL, cfg.APIPublicURL, job, logger); err != nil {
				logger.Error("job_failed", "job_id", job.ID, "error", err)
			}
		}
	}
}

func handleJob(ctx context.Context, repo *repository.Repository, telegram *integrations.TelegramClient, baseURL, apiBaseURL string, job models.NotificationJob, logger *slog.Logger) error {
	if logger == nil {
		logger = slog.Default()
	}
	logger.Info("job_processing", "job_id", job.ID, "kind", job.Kind, "user_id", job.UserID, "event_id", job.EventID, "run_at", job.RunAt)
	chatID, err := repo.GetUserTelegramID(ctx, job.UserID)
	if err != nil {
		return repo.UpdateNotificationJobStatus(ctx, job.ID, "failed", job.Attempts+1, err.Error(), nil)
	}

	message := buildNotification(job, baseURL, apiBaseURL)
	if message.Text == "" {
		return repo.UpdateNotificationJobStatus(ctx, job.ID, "failed", job.Attempts+1, "unknown job kind", nil)
	}

	var markup *integrations.ReplyMarkup
	if message.ButtonURL != "" {
		markup = &integrations.ReplyMarkup{
			InlineKeyboard: [][]integrations.InlineKeyboardButton{
				{
					{
						Text:   message.ButtonText,
						WebApp: &integrations.WebAppInfo{URL: message.ButtonURL},
					},
				},
			},
		}
	}

	var sendErr error
	sent := false
	if message.PhotoURL != "" {
		sendErr = telegram.SendPhotoWithMarkup(chatID, message.PhotoURL, message.Text, markup)
		if sendErr != nil && message.FallbackPhotoURL != "" && message.FallbackPhotoURL != message.PhotoURL {
			sendErr = telegram.SendPhotoWithMarkup(chatID, message.FallbackPhotoURL, message.Text, markup)
		}
		if sendErr == nil {
			sent = true
		}
	}
	if !sent {
		sendErr = telegram.SendMessageWithMarkup(chatID, message.Text, markup)
		if sendErr == nil {
			sent = true
		}
	}

	if !sent && sendErr != nil {
		attempts := job.Attempts + 1
		if attempts >= 3 {
			return repo.UpdateNotificationJobStatus(ctx, job.ID, "failed", attempts, sendErr.Error(), nil)
		}
		delay := time.Duration(1<<attempts) * time.Minute
		nextRun := time.Now().Add(delay)
		return repo.UpdateNotificationJobStatus(ctx, job.ID, "pending", attempts, sendErr.Error(), &nextRun)
	}

	if err := repo.UpdateNotificationJobStatus(ctx, job.ID, "sent", job.Attempts, "", nil); err != nil {
		return err
	}
	logger.Info("job_sent", "job_id", job.ID, "kind", job.Kind, "user_id", job.UserID)
	return nil
}

type notificationMessage struct {
	Text             string
	PhotoURL         string
	FallbackPhotoURL string
	ButtonURL        string
	ButtonText       string
}

func buildNotification(job models.NotificationJob, baseURL, apiBaseURL string) notificationMessage {
	title := payloadString(job.Payload, "title")
	eventURL := buildEventURL(baseURL, extractEventID(job))
	switch job.Kind {
	case "event_created":
		return buildEventCard(job, baseURL, apiBaseURL, "Новое событие")
	case "event_nearby":
		return buildEventCard(job, baseURL, apiBaseURL, "Событие рядом")
	case "joined":
		return notificationMessage{
			Text:       withTitle("Вы присоединились к событию", title),
			ButtonURL:  eventURL,
			ButtonText: buttonText(eventURL),
		}
	case "reminder_60m":
		return notificationMessage{
			Text:       withTitle("Напоминание: событие начнётся через 60 минут", title),
			ButtonURL:  eventURL,
			ButtonText: buttonText(eventURL),
		}
	default:
		return notificationMessage{}
	}
}

func buildEventCard(job models.NotificationJob, baseURL, apiBaseURL, heading string) notificationMessage {
	title := payloadString(job.Payload, "title")
	startsAt := formatStartsAt(payloadString(job.Payload, "startsAt"))
	address := payloadString(job.Payload, "addressLabel")
	photoURL := payloadString(job.Payload, "photoUrl")
	if photoURL == "" {
		photoURL = payloadString(job.Payload, "thumbnailUrl")
	}
	if photoURL != "" && !strings.HasPrefix(photoURL, "http://") && !strings.HasPrefix(photoURL, "https://") {
		photoURL = ""
	}
	mediaBaseURL := strings.TrimSpace(apiBaseURL)
	if mediaBaseURL == "" {
		mediaBaseURL = payloadString(job.Payload, "apiBaseUrl")
	}
	previewURL := buildMediaPreviewURL(mediaBaseURL, extractEventID(job))
	if previewURL == "" {
		previewURL = buildMediaPreviewURL(baseURL, extractEventID(job))
	}
	if photoURL == "" {
		photoURL = previewURL
		previewURL = ""
	}

	lines := make([]string, 0, 4)
	if heading != "" {
		lines = append(lines, heading)
	}
	if title != "" {
		lines = append(lines, title)
	}
	if startsAt != "" {
		lines = append(lines, startsAt)
	}
	if address != "" {
		lines = append(lines, address)
	}
	text := strings.Join(lines, "\n")
	if text == "" {
		text = heading
	}
	eventURL := buildEventURL(baseURL, extractEventID(job))

	return notificationMessage{
		Text:             text,
		PhotoURL:         photoURL,
		FallbackPhotoURL: previewURL,
		ButtonURL:        eventURL,
		ButtonText:       buttonText(eventURL),
	}
}

func payloadString(payload map[string]interface{}, key string) string {
	if payload == nil {
		return ""
	}
	raw, ok := payload[key]
	if !ok || raw == nil {
		return ""
	}
	switch value := raw.(type) {
	case string:
		return value
	case fmt.Stringer:
		return value.String()
	default:
		return fmt.Sprintf("%v", value)
	}
}

func extractEventID(job models.NotificationJob) int64 {
	if job.EventID != nil {
		return *job.EventID
	}
	return payloadInt64(job.Payload, "eventId")
}

func payloadInt64(payload map[string]interface{}, key string) int64 {
	if payload == nil {
		return 0
	}
	raw, ok := payload[key]
	if !ok || raw == nil {
		return 0
	}
	switch value := raw.(type) {
	case int64:
		return value
	case float64:
		return int64(value)
	case int:
		return int64(value)
	case string:
		parsed, err := strconv.ParseInt(value, 10, 64)
		if err == nil {
			return parsed
		}
	}
	return 0
}

func formatStartsAt(value string) string {
	if value == "" {
		return ""
	}
	parsed, err := time.Parse(time.RFC3339, value)
	if err != nil {
		return value
	}
	return parsed.Format("2006-01-02 15:04")
}

func buttonText(url string) string {
	if url == "" {
		return ""
	}
	return "Открыть событие"
}

func buildEventURL(baseURL string, eventID int64) string {
	if baseURL == "" || eventID <= 0 {
		return ""
	}
	parsed, err := url.Parse(baseURL)
	if err != nil || parsed.Scheme == "" {
		separator := "?"
		if strings.Contains(baseURL, "?") {
			separator = "&"
		}
		return fmt.Sprintf("%s%seventId=%d", baseURL, separator, eventID)
	}
	query := parsed.Query()
	query.Set("eventId", strconv.FormatInt(eventID, 10))
	parsed.RawQuery = query.Encode()
	parsed.Fragment = mergeEventIDIntoFragment(parsed.Fragment, eventID)
	return parsed.String()
}

func buildMediaPreviewURL(baseURL string, eventID int64) string {
	if baseURL == "" || eventID <= 0 {
		return ""
	}
	parsed, err := url.Parse(baseURL)
	if err != nil || parsed.Scheme == "" || parsed.Host == "" {
		return ""
	}
	parsed.RawQuery = ""
	parsed.Fragment = ""
	basePath := strings.TrimSpace(parsed.Path)
	parsed.Path = path.Join("/", basePath, "media", "events", strconv.FormatInt(eventID, 10), "0")
	return parsed.String()
}

func withTitle(prefix, title string) string {
	trimmed := strings.TrimSpace(title)
	if trimmed == "" {
		return prefix
	}
	return fmt.Sprintf("%s: %s", prefix, trimmed)
}

func mergeEventIDIntoFragment(fragment string, eventID int64) string {
	if eventID <= 0 {
		return fragment
	}
	if fragment == "" {
		return fmt.Sprintf("eventId=%d", eventID)
	}
	if strings.Contains(fragment, "eventId=") {
		return fragment
	}
	// Only touch query-like fragments (Telegram uses them for tgWebAppData).
	if strings.Contains(fragment, "=") {
		parsed, err := url.ParseQuery(fragment)
		if err == nil {
			parsed.Set("eventId", strconv.FormatInt(eventID, 10))
			return parsed.Encode()
		}
		return fragment + "&eventId=" + strconv.FormatInt(eventID, 10)
	}
	return fragment
}
