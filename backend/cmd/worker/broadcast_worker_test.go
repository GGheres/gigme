package main

import (
	"context"
	"errors"
	"os"
	"testing"
	"time"

	"gigme/backend/internal/db"
	"gigme/backend/internal/integrations"
	"gigme/backend/internal/repository"

	"github.com/jackc/pgx/v5/pgxpool"
)

type fakeTelegram struct {
	sent            []int64
	failWithMarkup  bool
	plainTextSends  int
	markupSendTries int
}

func (f *fakeTelegram) SendMessageWithMarkup(chatID int64, text string, markup *integrations.ReplyMarkup) error {
	if markup != nil {
		f.markupSendTries++
		if f.failWithMarkup {
			return errors.New("markup rejected")
		}
	} else {
		f.plainTextSends++
	}
	f.sent = append(f.sent, chatID)
	return nil
}

func (f *fakeTelegram) SendPhotoWithMarkup(chatID int64, photoURL, caption string, markup *integrations.ReplyMarkup) error {
	return nil
}

func TestBroadcastWorkerSendsJobs(t *testing.T) {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		t.Skip("DATABASE_URL not set")
	}

	ctx := context.Background()
	pool, err := db.NewPool(ctx, dsn)
	if err != nil {
		t.Fatalf("db connection failed: %v", err)
	}
	defer pool.Close()

	repo := repository.New(pool)

	adminID, err := insertWorkerUser(ctx, pool, 998001, "admin")
	if err != nil {
		t.Fatalf("insert admin user: %v", err)
	}
	user1, err := insertWorkerUser(ctx, pool, 998002, "user1")
	if err != nil {
		t.Fatalf("insert user1: %v", err)
	}
	user2, err := insertWorkerUser(ctx, pool, 998003, "user2")
	if err != nil {
		t.Fatalf("insert user2: %v", err)
	}

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, "DELETE FROM admin_broadcast_jobs WHERE target_user_id IN ($1, $2)", user1, user2)
		_, _ = pool.Exec(ctx, "DELETE FROM admin_broadcasts WHERE admin_user_id = $1", adminID)
		_, _ = pool.Exec(ctx, "DELETE FROM users WHERE id = $1", adminID)
		_, _ = pool.Exec(ctx, "DELETE FROM users WHERE id = $1", user1)
		_, _ = pool.Exec(ctx, "DELETE FROM users WHERE id = $1", user2)
	})

	broadcastID, err := repo.CreateAdminBroadcast(ctx, adminID, "selected", map[string]interface{}{"message": "Hello"})
	if err != nil {
		t.Fatalf("create broadcast: %v", err)
	}
	_, err = repo.InsertAdminBroadcastJobsForSelected(ctx, broadcastID, []int64{user1, user2})
	if err != nil {
		t.Fatalf("insert jobs: %v", err)
	}
	if err := repo.UpdateAdminBroadcastStatus(ctx, broadcastID, "processing"); err != nil {
		t.Fatalf("update broadcast status: %v", err)
	}

	jobs, err := repo.FetchPendingAdminBroadcastJobs(ctx, 10)
	if err != nil {
		t.Fatalf("fetch jobs: %v", err)
	}
	if len(jobs) != 2 {
		t.Fatalf("expected 2 jobs, got %d", len(jobs))
	}

	fake := &fakeTelegram{}
	limiter := time.NewTicker(time.Millisecond)
	defer limiter.Stop()
	if err := processBroadcastJobs(ctx, repo, fake, jobs, limiter, nil); err != nil {
		t.Fatalf("process broadcast jobs: %v", err)
	}
	if len(fake.sent) != 2 {
		t.Fatalf("expected 2 sends, got %d", len(fake.sent))
	}

	var sentCount int
	if err := pool.QueryRow(ctx, `SELECT count(*) FROM admin_broadcast_jobs WHERE broadcast_id = $1 AND status = 'sent'`, broadcastID).Scan(&sentCount); err != nil {
		t.Fatalf("count sent: %v", err)
	}
	if sentCount != 2 {
		t.Fatalf("expected 2 sent jobs, got %d", sentCount)
	}

	var status string
	if err := pool.QueryRow(ctx, `SELECT status FROM admin_broadcasts WHERE id = $1`, broadcastID).Scan(&status); err != nil {
		t.Fatalf("broadcast status: %v", err)
	}
	if status != "done" {
		t.Fatalf("expected broadcast status done, got %s", status)
	}
}

func TestBroadcastWorkerFallsBackToPlainTextWhenMarkupRejected(t *testing.T) {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		t.Skip("DATABASE_URL not set")
	}

	ctx := context.Background()
	pool, err := db.NewPool(ctx, dsn)
	if err != nil {
		t.Fatalf("db connection failed: %v", err)
	}
	defer pool.Close()

	repo := repository.New(pool)

	adminID, err := insertWorkerUser(ctx, pool, 998011, "admin_fallback")
	if err != nil {
		t.Fatalf("insert admin user: %v", err)
	}
	userID, err := insertWorkerUser(ctx, pool, 998012, "user_fallback")
	if err != nil {
		t.Fatalf("insert user: %v", err)
	}

	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, "DELETE FROM admin_broadcast_jobs WHERE target_user_id = $1", userID)
		_, _ = pool.Exec(ctx, "DELETE FROM admin_broadcasts WHERE admin_user_id = $1", adminID)
		_, _ = pool.Exec(ctx, "DELETE FROM users WHERE id = $1", adminID)
		_, _ = pool.Exec(ctx, "DELETE FROM users WHERE id = $1", userID)
	})

	broadcastID, err := repo.CreateAdminBroadcast(ctx, adminID, "selected", map[string]interface{}{
		"message": "Hello",
		"buttons": []map[string]string{
			{
				"text": "Open",
				"url":  "https://example.com",
			},
		},
	})
	if err != nil {
		t.Fatalf("create broadcast: %v", err)
	}
	_, err = repo.InsertAdminBroadcastJobsForSelected(ctx, broadcastID, []int64{userID})
	if err != nil {
		t.Fatalf("insert jobs: %v", err)
	}
	if err := repo.UpdateAdminBroadcastStatus(ctx, broadcastID, "processing"); err != nil {
		t.Fatalf("update broadcast status: %v", err)
	}

	jobs, err := repo.FetchPendingAdminBroadcastJobs(ctx, 10)
	if err != nil {
		t.Fatalf("fetch jobs: %v", err)
	}
	if len(jobs) != 1 {
		t.Fatalf("expected 1 job, got %d", len(jobs))
	}

	fake := &fakeTelegram{failWithMarkup: true}
	limiter := time.NewTicker(time.Millisecond)
	defer limiter.Stop()
	if err := processBroadcastJobs(ctx, repo, fake, jobs, limiter, nil); err != nil {
		t.Fatalf("process broadcast jobs: %v", err)
	}
	if fake.markupSendTries == 0 {
		t.Fatalf("expected markup send attempt")
	}
	if fake.plainTextSends == 0 {
		t.Fatalf("expected plain text fallback send")
	}
	if len(fake.sent) != 1 {
		t.Fatalf("expected 1 sent message, got %d", len(fake.sent))
	}

	var status string
	if err := pool.QueryRow(ctx, `SELECT status FROM admin_broadcast_jobs WHERE broadcast_id = $1`, broadcastID).Scan(&status); err != nil {
		t.Fatalf("job status: %v", err)
	}
	if status != "sent" {
		t.Fatalf("expected job status sent, got %s", status)
	}
}

func insertWorkerUser(ctx context.Context, pool *pgxpool.Pool, telegramID int64, suffix string) (int64, error) {
	row := pool.QueryRow(ctx, `INSERT INTO users (telegram_id, username, first_name, last_name)
VALUES ($1, $2, $3, $4)
RETURNING id;`, telegramID, "worker_"+suffix, "Test", "User")
	var id int64
	if err := row.Scan(&id); err != nil {
		return 0, err
	}
	return id, nil
}
