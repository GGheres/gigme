package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"log/slog"
	"net/url"
	"os"
	"path"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

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
	rateLimiter := time.NewTicker(time.Second / 20)
	defer rateLimiter.Stop()
	for {
		didWork := false
		if err := repo.RequeueStaleProcessing(ctx, 10*time.Minute); err != nil {
			logger.Warn("requeue_stale_jobs_error", "error", err)
		}
		jobs, err := repo.FetchDueNotificationJobs(ctx, 100)
		if err != nil {
			logger.Error("fetch_jobs_error", "error", err)
			time.Sleep(5 * time.Second)
			continue
		}
		if len(jobs) > 0 {
			didWork = true
			for _, job := range jobs {
				if err := handleJob(ctx, repo, telegram, cfg.BaseURL, cfg.APIPublicURL, job, logger); err != nil {
					logger.Error("job_failed", "job_id", job.ID, "error", err)
				}
			}
		}

		if err := repo.RequeueStaleAdminBroadcastJobs(ctx, 10*time.Minute); err != nil {
			logger.Warn("requeue_stale_broadcast_jobs_error", "error", err)
		}
		broadcastJobs, err := repo.FetchPendingAdminBroadcastJobs(ctx, 100)
		if err != nil {
			logger.Error("fetch_broadcast_jobs_error", "error", err)
			time.Sleep(5 * time.Second)
			continue
		}
		if len(broadcastJobs) > 0 {
			didWork = true
			if err := processBroadcastJobs(ctx, repo, telegram, broadcastJobs, rateLimiter, logger); err != nil {
				logger.Error("broadcast_jobs_error", "error", err)
			}
		}
		if !didWork {
			time.Sleep(10 * time.Second)
		}
	}
}

type TelegramSender interface {
	SendMessageWithMarkup(chatID int64, text string, markup *integrations.ReplyMarkup) error
	SendPhotoWithMarkup(chatID int64, photoURL, caption string, markup *integrations.ReplyMarkup) error
}

func handleJob(ctx context.Context, repo *repository.Repository, telegram TelegramSender, baseURL, apiBaseURL string, job models.NotificationJob, logger *slog.Logger) error {
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
	photoCaption := truncateRunes(message.Text, 1024)
	if photoCaption == "" {
		photoCaption = message.Text
	}
	for _, photoURL := range message.PhotoURLs {
		sendErr = telegram.SendPhotoWithMarkup(chatID, photoURL, photoCaption, markup)
		if sendErr == nil {
			sent = true
			break
		}
		logger.Warn("job_photo_send_failed", "job_id", job.ID, "photo_url", photoURL, "error", sendErr)
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
	Text       string
	PhotoURLs  []string
	ButtonURL  string
	ButtonText string
}

func buildNotification(job models.NotificationJob, baseURL, apiBaseURL string) notificationMessage {
	title := payloadString(job.Payload, "title")
	eventURL := buildEventURL(baseURL, extractEventID(job))
	switch job.Kind {
	case "event_created":
		return buildEventCard(job, baseURL, apiBaseURL, "Новое событие")
	case "event_nearby":
		return buildEventCard(job, baseURL, apiBaseURL, "Событие рядом")
	case "comment_added":
		return buildCommentNotification(job, baseURL, apiBaseURL)
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
	case "payment_confirmed":
		orderID := strings.TrimSpace(payloadString(job.Payload, "orderId"))
		amount := strings.TrimSpace(payloadString(job.Payload, "amount"))
		currency := strings.TrimSpace(payloadString(job.Payload, "currency"))
		lines := []string{"Ваш платеж подтвержден."}
		if orderID != "" {
			lines = append(lines, fmt.Sprintf("Заказ: %s", orderID))
		}
		if title != "" {
			lines = append(lines, fmt.Sprintf("Событие: %s", title))
		}
		if amount != "" {
			if currency != "" {
				lines = append(lines, fmt.Sprintf("Сумма: %s %s", amount, currency))
			} else {
				lines = append(lines, fmt.Sprintf("Сумма: %s", amount))
			}
		}
		return notificationMessage{
			Text:       strings.Join(lines, "\n"),
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
	photoURLs := buildNotificationPhotoURLs(job, baseURL, apiBaseURL)

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
		Text:       text,
		PhotoURLs:  photoURLs,
		ButtonURL:  eventURL,
		ButtonText: buttonText(eventURL),
	}
}

func buildCommentNotification(job models.NotificationJob, baseURL, apiBaseURL string) notificationMessage {
	title := payloadString(job.Payload, "title")
	commenter := payloadString(job.Payload, "commenterName")
	comment := strings.TrimSpace(payloadString(job.Payload, "comment"))
	if commenter == "" {
		commenter = "Новый комментарий"
	}
	if comment != "" {
		comment = truncateRunes(comment, 200)
	}
	lines := make([]string, 0, 3)
	if title != "" {
		lines = append(lines, fmt.Sprintf("Новый комментарий к событию: %s", title))
	} else {
		lines = append(lines, "Новый комментарий к событию")
	}
	if comment != "" {
		lines = append(lines, fmt.Sprintf("%s: %s", commenter, comment))
	} else if commenter != "" {
		lines = append(lines, commenter)
	}
	eventURL := buildEventURL(baseURL, extractEventID(job))
	photoURLs := buildNotificationPhotoURLs(job, baseURL, apiBaseURL)
	return notificationMessage{
		Text:       strings.Join(lines, "\n"),
		PhotoURLs:  photoURLs,
		ButtonURL:  eventURL,
		ButtonText: buttonText(eventURL),
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
	baseURL = normalizeWebAppBaseURL(baseURL)
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

func normalizeWebAppBaseURL(raw string) string {
	base := strings.TrimSpace(raw)
	if base == "" {
		return ""
	}

	parsed, err := url.Parse(base)
	if err != nil {
		return base
	}

	// Notification WebApp buttons should open the app entrypoint directly.
	if parsed.Scheme == "" || parsed.Host == "" {
		trimmedPath := strings.TrimSpace(parsed.Path)
		if strings.HasPrefix(trimmedPath, "/space_app") {
			return trimmedPath
		}
		if strings.HasPrefix(trimmedPath, "/") {
			return "/space_app"
		}
		return base
	}

	parsed.Path = "/space_app"
	parsed.RawQuery = ""
	parsed.Fragment = ""
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

func buildNotificationPhotoURLs(job models.NotificationJob, baseURL, apiBaseURL string) []string {
	mediaBaseURL := strings.TrimSpace(apiBaseURL)
	if mediaBaseURL == "" {
		mediaBaseURL = payloadString(job.Payload, "apiBaseUrl")
	}
	eventID := extractEventID(job)
	photoURLs := buildMediaPreviewCandidates(eventID, mediaBaseURL, baseURL)

	photoURL := payloadString(job.Payload, "photoUrl")
	if photoURL == "" {
		photoURL = payloadString(job.Payload, "thumbnailUrl")
	}
	return appendUniqueStrings(
		photoURLs,
		normalizePhotoURL(photoURL, mediaBaseURL, baseURL),
		normalizePhotoURL(photoURL, buildAPIBaseURL(mediaBaseURL), buildAPIBaseURL(baseURL)),
	)
}

func buildMediaPreviewCandidates(eventID int64, apiBaseURL, baseURL string) []string {
	return appendUniqueStrings(
		nil,
		buildMediaPreviewURL(apiBaseURL, eventID),
		buildMediaPreviewURL(buildAPIBaseURL(apiBaseURL), eventID),
		buildMediaPreviewURL(buildAPIBaseURL(baseURL), eventID),
		buildMediaPreviewURL(baseURL, eventID),
	)
}

func buildAPIBaseURL(baseURL string) string {
	parsed, err := url.Parse(strings.TrimSpace(baseURL))
	if err != nil || parsed.Scheme == "" || parsed.Host == "" {
		return ""
	}
	parsed.RawQuery = ""
	parsed.Fragment = ""
	parsed.Path = "/api"
	return parsed.String()
}

func normalizePhotoURL(raw string, baseURLs ...string) string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return ""
	}
	if parsed, err := url.Parse(raw); err == nil && parsed.Scheme != "" && parsed.Host != "" {
		scheme := strings.ToLower(parsed.Scheme)
		if scheme == "http" || scheme == "https" {
			return parsed.String()
		}
		return ""
	}
	if strings.HasPrefix(raw, "http://") || strings.HasPrefix(raw, "https://") {
		return raw
	}
	if strings.HasPrefix(raw, "//") {
		for _, baseURL := range baseURLs {
			parsed, err := url.Parse(strings.TrimSpace(baseURL))
			if err == nil && parsed.Scheme != "" {
				return parsed.Scheme + ":" + raw
			}
		}
		return ""
	}
	for _, baseURL := range baseURLs {
		parsed, err := url.Parse(strings.TrimSpace(baseURL))
		if err != nil || parsed.Scheme == "" || parsed.Host == "" {
			continue
		}
		parsed.RawQuery = ""
		parsed.Fragment = ""
		if strings.HasPrefix(raw, "/") {
			parsed.Path = path.Clean(raw)
		} else {
			basePath := strings.TrimSpace(parsed.Path)
			parsed.Path = path.Join("/", basePath, raw)
		}
		return parsed.String()
	}
	return ""
}

func appendUniqueStrings(target []string, values ...string) []string {
	if target == nil {
		target = make([]string, 0, len(values))
	}
	for _, value := range values {
		trimmed := strings.TrimSpace(value)
		if trimmed == "" {
			continue
		}
		seen := false
		for _, existing := range target {
			if existing == trimmed {
				seen = true
				break
			}
		}
		if !seen {
			target = append(target, trimmed)
		}
	}
	return target
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

func truncateRunes(value string, max int) string {
	if max <= 0 || value == "" {
		return ""
	}
	if utf8.RuneCountInString(value) <= max {
		return value
	}
	if max == 1 {
		return "…"
	}
	out := make([]rune, 0, max-1)
	for _, r := range value {
		out = append(out, r)
		if len(out) >= max-1 {
			break
		}
	}
	return string(out) + "…"
}

type broadcastPayload struct {
	Message string            `json:"message"`
	Buttons []broadcastButton `json:"buttons"`
}

type broadcastButton struct {
	Text string `json:"text"`
	URL  string `json:"url"`
}

func processBroadcastJobs(ctx context.Context, repo *repository.Repository, telegram TelegramSender, jobs []models.AdminBroadcastJob, limiter *time.Ticker, logger *slog.Logger) error {
	if logger == nil {
		logger = slog.Default()
	}
	payloadCache := make(map[int64]broadcastPayload)
	broadcastIDs := make(map[int64]struct{})

	for _, job := range jobs {
		payload, ok := payloadCache[job.BroadcastID]
		if !ok {
			loaded, err := loadBroadcastPayload(ctx, repo, job.BroadcastID)
			if err != nil {
				logger.Error("broadcast_payload_error", "broadcast_id", job.BroadcastID, "error", err)
				_ = repo.UpdateAdminBroadcastJobStatus(ctx, job.ID, "failed", job.Attempts, err.Error())
				continue
			}
			payload = loaded
			payloadCache[job.BroadcastID] = payload
		}
		if err := handleBroadcastJob(ctx, repo, telegram, job, payload, limiter, logger); err != nil {
			logger.Error("broadcast_job_failed", "job_id", job.ID, "broadcast_id", job.BroadcastID, "error", err)
		}
		broadcastIDs[job.BroadcastID] = struct{}{}
	}

	for id := range broadcastIDs {
		if _, err := repo.FinalizeAdminBroadcast(ctx, id); err != nil {
			logger.Warn("broadcast_finalize_error", "broadcast_id", id, "error", err)
		}
	}
	return nil
}

func loadBroadcastPayload(ctx context.Context, repo *repository.Repository, broadcastID int64) (broadcastPayload, error) {
	record, err := repo.GetAdminBroadcast(ctx, broadcastID)
	if err != nil {
		return broadcastPayload{}, err
	}
	if len(record.Payload) == 0 {
		return broadcastPayload{}, errors.New("empty broadcast payload")
	}
	var payload broadcastPayload
	encoded, err := json.Marshal(record.Payload)
	if err != nil {
		return broadcastPayload{}, err
	}
	if err := json.Unmarshal(encoded, &payload); err != nil {
		return broadcastPayload{}, err
	}
	if strings.TrimSpace(payload.Message) == "" {
		return broadcastPayload{}, errors.New("broadcast message missing")
	}
	return payload, nil
}

func handleBroadcastJob(ctx context.Context, repo *repository.Repository, telegram TelegramSender, job models.AdminBroadcastJob, payload broadcastPayload, limiter *time.Ticker, logger *slog.Logger) error {
	if logger == nil {
		logger = slog.Default()
	}
	blocked, err := repo.IsUserBlocked(ctx, job.TargetUserID)
	if err != nil {
		return repo.UpdateAdminBroadcastJobStatus(ctx, job.ID, "failed", job.Attempts, err.Error())
	}
	if blocked {
		return repo.UpdateAdminBroadcastJobStatus(ctx, job.ID, "failed", job.Attempts, "user blocked")
	}

	chatID, err := repo.GetUserTelegramID(ctx, job.TargetUserID)
	if err != nil {
		return repo.UpdateAdminBroadcastJobStatus(ctx, job.ID, "failed", job.Attempts+1, err.Error())
	}

	markup := buildBroadcastMarkup(payload.Buttons)
	attempts := job.Attempts
	var lastErr error
	for attempts < 3 {
		attempts++
		if limiter != nil {
			<-limiter.C
		}
		sendErr := telegram.SendMessageWithMarkup(chatID, payload.Message, markup)
		if sendErr == nil {
			return repo.UpdateAdminBroadcastJobStatus(ctx, job.ID, "sent", attempts, "")
		}
		if markup != nil {
			// Keep broadcast delivery resilient: fallback to plain text when markup is rejected.
			plainErr := telegram.SendMessageWithMarkup(chatID, payload.Message, nil)
			if plainErr == nil {
				logger.Warn(
					"broadcast_markup_rejected_plain_fallback_sent",
					"job_id",
					job.ID,
					"broadcast_id",
					job.BroadcastID,
					"error",
					sendErr,
				)
				return repo.UpdateAdminBroadcastJobStatus(ctx, job.ID, "sent", attempts, "")
			}
			lastErr = fmt.Errorf("send with markup failed: %v; fallback failed: %w", sendErr, plainErr)
		} else {
			lastErr = sendErr
		}
		if attempts < 3 {
			time.Sleep(time.Second * time.Duration(1<<(attempts-1)))
		}
	}
	if lastErr == nil {
		lastErr = errors.New("broadcast send failed")
	}
	return repo.UpdateAdminBroadcastJobStatus(ctx, job.ID, "failed", attempts, lastErr.Error())
}

func buildBroadcastMarkup(buttons []broadcastButton) *integrations.ReplyMarkup {
	if len(buttons) == 0 {
		return nil
	}
	rows := make([][]integrations.InlineKeyboardButton, 0, len(buttons))
	for _, button := range buttons {
		text := strings.TrimSpace(button.Text)
		url := strings.TrimSpace(button.URL)
		if text == "" || url == "" {
			continue
		}
		rows = append(rows, []integrations.InlineKeyboardButton{{Text: text, URL: url}})
	}
	if len(rows) == 0 {
		return nil
	}
	return &integrations.ReplyMarkup{InlineKeyboard: rows}
}
