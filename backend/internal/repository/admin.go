package repository

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"gigme/backend/internal/models"

	"github.com/jackc/pgx/v5"
)

func (r *Repository) TouchUserLastSeen(ctx context.Context, userID int64) error {
	_, err := r.pool.Exec(ctx, `UPDATE users SET last_seen_at = now(), updated_at = now() WHERE id = $1`, userID)
	return err
}

func (r *Repository) GetUserByTelegramID(ctx context.Context, telegramID int64) (models.User, error) {
	row := r.pool.QueryRow(ctx, `SELECT id, telegram_id, username, first_name, last_name, photo_url, rating, rating_count, balance_tokens, created_at, updated_at FROM users WHERE telegram_id = $1`, telegramID)
	var out models.User
	var username sql.NullString
	var lastName sql.NullString
	var photoURL sql.NullString
	if err := row.Scan(&out.ID, &out.TelegramID, &username, &out.FirstName, &lastName, &photoURL, &out.Rating, &out.RatingCount, &out.BalanceTokens, &out.CreatedAt, &out.UpdatedAt); err != nil {
		return out, err
	}
	if username.Valid {
		out.Username = username.String
	}
	if lastName.Valid {
		out.LastName = lastName.String
	}
	if photoURL.Valid {
		out.PhotoURL = photoURL.String
	}
	return out, nil
}

func (r *Repository) EnsureUserByTelegramID(ctx context.Context, telegramID int64, username, firstName, lastName string) (models.User, error) {
	user, err := r.GetUserByTelegramID(ctx, telegramID)
	if err == nil {
		return user, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return user, err
	}

	row := r.pool.QueryRow(ctx, `
INSERT INTO users (telegram_id, username, first_name, last_name, last_seen_at)
VALUES ($1, $2, $3, $4, now())
RETURNING id, telegram_id, username, first_name, last_name, photo_url, rating, rating_count, balance_tokens, created_at, updated_at;`,
		telegramID,
		nullString(username),
		firstName,
		nullString(lastName),
	)
	var out models.User
	var usernameNull sql.NullString
	var lastNameNull sql.NullString
	var photoURL sql.NullString
	if err := row.Scan(&out.ID, &out.TelegramID, &usernameNull, &out.FirstName, &lastNameNull, &photoURL, &out.Rating, &out.RatingCount, &out.BalanceTokens, &out.CreatedAt, &out.UpdatedAt); err != nil {
		return out, err
	}
	if usernameNull.Valid {
		out.Username = usernameNull.String
	}
	if lastNameNull.Valid {
		out.LastName = lastNameNull.String
	}
	if photoURL.Valid {
		out.PhotoURL = photoURL.String
	}
	return out, nil
}

func (r *Repository) IsUserBlocked(ctx context.Context, userID int64) (bool, error) {
	row := r.pool.QueryRow(ctx, `SELECT is_blocked FROM users WHERE id = $1`, userID)
	var blocked bool
	if err := row.Scan(&blocked); err != nil {
		return false, err
	}
	return blocked, nil
}

func (r *Repository) BlockUser(ctx context.Context, userID int64, reason string) error {
	_, err := r.pool.Exec(ctx, `UPDATE users SET is_blocked = true, blocked_reason = $2, blocked_at = now(), updated_at = now() WHERE id = $1`, userID, nullString(reason))
	return err
}

func (r *Repository) UnblockUser(ctx context.Context, userID int64) error {
	_, err := r.pool.Exec(ctx, `UPDATE users SET is_blocked = false, blocked_reason = NULL, blocked_at = NULL, updated_at = now() WHERE id = $1`, userID)
	return err
}

func (r *Repository) GetAdminUser(ctx context.Context, userID int64) (models.AdminUser, error) {
	row := r.pool.QueryRow(ctx, `
SELECT id, telegram_id, username, first_name, last_name, photo_url,
	rating, rating_count, balance_tokens,
	is_blocked, blocked_reason, blocked_at, last_seen_at,
	created_at, updated_at
FROM users
WHERE id = $1;`, userID)
	var out models.AdminUser
	var username sql.NullString
	var lastName sql.NullString
	var photoURL sql.NullString
	var blockedReason sql.NullString
	var blockedAt sql.NullTime
	var lastSeen sql.NullTime
	if err := row.Scan(
		&out.ID,
		&out.TelegramID,
		&username,
		&out.FirstName,
		&lastName,
		&photoURL,
		&out.Rating,
		&out.RatingCount,
		&out.BalanceTokens,
		&out.IsBlocked,
		&blockedReason,
		&blockedAt,
		&lastSeen,
		&out.CreatedAt,
		&out.UpdatedAt,
	); err != nil {
		return out, err
	}
	if username.Valid {
		out.Username = username.String
	}
	if lastName.Valid {
		out.LastName = lastName.String
	}
	if photoURL.Valid {
		out.PhotoURL = photoURL.String
	}
	if blockedReason.Valid {
		out.BlockedReason = blockedReason.String
	}
	if blockedAt.Valid {
		val := blockedAt.Time
		out.BlockedAt = &val
	}
	if lastSeen.Valid {
		val := lastSeen.Time
		out.LastSeenAt = &val
	}
	return out, nil
}

func (r *Repository) ListAdminUsers(ctx context.Context, search string, blocked *bool, limit, offset int) ([]models.AdminUser, int, error) {
	clauses := make([]string, 0)
	args := make([]interface{}, 0)
	idx := 1

	search = strings.TrimSpace(search)
	if search != "" {
		like := fmt.Sprintf("%%%s%%", search)
		clauses = append(clauses, fmt.Sprintf("(username ILIKE $%d OR first_name ILIKE $%d OR last_name ILIKE $%d OR CAST(telegram_id AS text) ILIKE $%d)", idx, idx, idx, idx))
		args = append(args, like)
		idx++
	}
	if blocked != nil {
		clauses = append(clauses, fmt.Sprintf("is_blocked = $%d", idx))
		args = append(args, *blocked)
		idx++
	}

	query := `
SELECT id, telegram_id, username, first_name, last_name, photo_url,
	rating, rating_count, balance_tokens,
	is_blocked, blocked_reason, blocked_at, last_seen_at,
	created_at, updated_at,
	COUNT(*) OVER() AS total
FROM users`
	if len(clauses) > 0 {
		query += " WHERE " + strings.Join(clauses, " AND ")
	}
	query += fmt.Sprintf(" ORDER BY last_seen_at DESC NULLS LAST, created_at DESC LIMIT $%d OFFSET $%d;", idx, idx+1)
	args = append(args, limit, offset)

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	items := make([]models.AdminUser, 0)
	total := 0
	for rows.Next() {
		var item models.AdminUser
		var username sql.NullString
		var lastName sql.NullString
		var photoURL sql.NullString
		var blockedReason sql.NullString
		var blockedAt sql.NullTime
		var lastSeen sql.NullTime
		var rowTotal int
		if err := rows.Scan(
			&item.ID,
			&item.TelegramID,
			&username,
			&item.FirstName,
			&lastName,
			&photoURL,
			&item.Rating,
			&item.RatingCount,
			&item.BalanceTokens,
			&item.IsBlocked,
			&blockedReason,
			&blockedAt,
			&lastSeen,
			&item.CreatedAt,
			&item.UpdatedAt,
			&rowTotal,
		); err != nil {
			return nil, 0, err
		}
		if username.Valid {
			item.Username = username.String
		}
		if lastName.Valid {
			item.LastName = lastName.String
		}
		if photoURL.Valid {
			item.PhotoURL = photoURL.String
		}
		if blockedReason.Valid {
			item.BlockedReason = blockedReason.String
		}
		if blockedAt.Valid {
			val := blockedAt.Time
			item.BlockedAt = &val
		}
		if lastSeen.Valid {
			val := lastSeen.Time
			item.LastSeenAt = &val
		}
		total = rowTotal
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, err
	}
	return items, total, nil
}

func (r *Repository) CreateAdminBroadcast(ctx context.Context, adminUserID int64, audience string, payload map[string]interface{}) (int64, error) {
	payloadBytes, err := json.Marshal(payload)
	if err != nil {
		return 0, err
	}
	row := r.pool.QueryRow(ctx, `
INSERT INTO admin_broadcasts (admin_user_id, audience, payload, status)
VALUES ($1, $2, $3, 'pending')
RETURNING id;`, adminUserID, audience, payloadBytes)
	var id int64
	if err := row.Scan(&id); err != nil {
		return 0, err
	}
	return id, nil
}

func (r *Repository) UpdateAdminBroadcastStatus(ctx context.Context, broadcastID int64, status string) error {
	_, err := r.pool.Exec(ctx, `UPDATE admin_broadcasts SET status = $1, updated_at = now() WHERE id = $2`, status, broadcastID)
	return err
}

func (r *Repository) InsertAdminBroadcastJobsForAll(ctx context.Context, broadcastID int64) (int64, error) {
	command, err := r.pool.Exec(ctx, `
INSERT INTO admin_broadcast_jobs (broadcast_id, target_user_id)
SELECT $1, id
FROM users
WHERE is_blocked = false AND telegram_id IS NOT NULL;`, broadcastID)
	if err != nil {
		return 0, err
	}
	return command.RowsAffected(), nil
}

func (r *Repository) InsertAdminBroadcastJobsForSelected(ctx context.Context, broadcastID int64, userIDs []int64) (int64, error) {
	if len(userIDs) == 0 {
		return 0, nil
	}
	command, err := r.pool.Exec(ctx, `
INSERT INTO admin_broadcast_jobs (broadcast_id, target_user_id)
SELECT $1, id
FROM users
WHERE id = ANY($2) AND is_blocked = false AND telegram_id IS NOT NULL;`, broadcastID, userIDs)
	if err != nil {
		return 0, err
	}
	return command.RowsAffected(), nil
}

func (r *Repository) InsertAdminBroadcastJobsForFilter(ctx context.Context, broadcastID int64, minBalance *int64, lastSeenAfter *time.Time) (int64, error) {
	clauses := []string{"is_blocked = false", "telegram_id IS NOT NULL"}
	args := []interface{}{broadcastID}
	idx := 2
	if minBalance != nil {
		clauses = append(clauses, fmt.Sprintf("balance_tokens >= $%d", idx))
		args = append(args, *minBalance)
		idx++
	}
	if lastSeenAfter != nil {
		clauses = append(clauses, fmt.Sprintf("last_seen_at >= $%d", idx))
		args = append(args, *lastSeenAfter)
		idx++
	}
	query := fmt.Sprintf(`
INSERT INTO admin_broadcast_jobs (broadcast_id, target_user_id)
SELECT $1, id
FROM users
WHERE %s;`, strings.Join(clauses, " AND "))
	command, err := r.pool.Exec(ctx, query, args...)
	if err != nil {
		return 0, err
	}
	return command.RowsAffected(), nil
}

func (r *Repository) FetchPendingAdminBroadcastJobs(ctx context.Context, limit int) ([]models.AdminBroadcastJob, error) {
	query := `
WITH cte AS (
	SELECT j.id
	FROM admin_broadcast_jobs j
	JOIN admin_broadcasts b ON b.id = j.broadcast_id
	WHERE j.status = 'pending' AND b.status = 'processing'
	ORDER BY j.created_at ASC
	LIMIT $1
	FOR UPDATE SKIP LOCKED
)
UPDATE admin_broadcast_jobs j
SET status = 'processing', updated_at = now()
FROM cte
WHERE j.id = cte.id
RETURNING j.id, j.broadcast_id, j.target_user_id, j.status, j.attempts, COALESCE(j.last_error, '');`

	rows, err := r.pool.Query(ctx, query, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	jobs := make([]models.AdminBroadcastJob, 0)
	for rows.Next() {
		var job models.AdminBroadcastJob
		if err := rows.Scan(&job.ID, &job.BroadcastID, &job.TargetUserID, &job.Status, &job.Attempts, &job.LastError); err != nil {
			return nil, err
		}
		jobs = append(jobs, job)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return jobs, nil
}

func (r *Repository) UpdateAdminBroadcastJobStatus(ctx context.Context, jobID int64, status string, attempts int, lastError string) error {
	_, err := r.pool.Exec(ctx, `UPDATE admin_broadcast_jobs SET status = $1, attempts = $2, last_error = $3, updated_at = now() WHERE id = $4`, status, attempts, nullString(lastError), jobID)
	return err
}

func (r *Repository) RequeueStaleAdminBroadcastJobs(ctx context.Context, staleAfter time.Duration) error {
	interval := fmt.Sprintf("%d seconds", int(staleAfter.Seconds()))
	_, err := r.pool.Exec(ctx, `UPDATE admin_broadcast_jobs SET status = 'pending', updated_at = now() WHERE status = 'processing' AND updated_at <= now() - $1::interval`, interval)
	return err
}

func (r *Repository) ListAdminBroadcasts(ctx context.Context, limit, offset int) ([]models.AdminBroadcast, int, error) {
	query := `
SELECT b.id, b.admin_user_id, b.audience, b.payload, b.status, b.created_at, b.updated_at,
	COALESCE(stats.total, 0) AS targeted,
	COALESCE(stats.sent, 0) AS sent,
	COALESCE(stats.failed, 0) AS failed,
	COUNT(*) OVER() AS total
FROM admin_broadcasts b
LEFT JOIN LATERAL (
	SELECT COUNT(*) AS total,
		COUNT(*) FILTER (WHERE status = 'sent') AS sent,
		COUNT(*) FILTER (WHERE status = 'failed') AS failed
	FROM admin_broadcast_jobs j
	WHERE j.broadcast_id = b.id
) stats ON true
ORDER BY b.created_at DESC
LIMIT $1 OFFSET $2;`

	rows, err := r.pool.Query(ctx, query, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	items := make([]models.AdminBroadcast, 0)
	total := 0
	for rows.Next() {
		var item models.AdminBroadcast
		var payloadBytes []byte
		var rowTotal int
		if err := rows.Scan(
			&item.ID,
			&item.AdminUserID,
			&item.Audience,
			&payloadBytes,
			&item.Status,
			&item.CreatedAt,
			&item.UpdatedAt,
			&item.Targeted,
			&item.Sent,
			&item.Failed,
			&rowTotal,
		); err != nil {
			return nil, 0, err
		}
		if len(payloadBytes) > 0 {
			_ = json.Unmarshal(payloadBytes, &item.Payload)
		}
		total = rowTotal
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, err
	}
	return items, total, nil
}

func (r *Repository) GetAdminBroadcast(ctx context.Context, broadcastID int64) (models.AdminBroadcast, error) {
	query := `
SELECT b.id, b.admin_user_id, b.audience, b.payload, b.status, b.created_at, b.updated_at,
	COALESCE(stats.total, 0) AS targeted,
	COALESCE(stats.sent, 0) AS sent,
	COALESCE(stats.failed, 0) AS failed
FROM admin_broadcasts b
LEFT JOIN LATERAL (
	SELECT COUNT(*) AS total,
		COUNT(*) FILTER (WHERE status = 'sent') AS sent,
		COUNT(*) FILTER (WHERE status = 'failed') AS failed
	FROM admin_broadcast_jobs j
	WHERE j.broadcast_id = b.id
) stats ON true
WHERE b.id = $1;`

	row := r.pool.QueryRow(ctx, query, broadcastID)
	var item models.AdminBroadcast
	var payloadBytes []byte
	if err := row.Scan(
		&item.ID,
		&item.AdminUserID,
		&item.Audience,
		&payloadBytes,
		&item.Status,
		&item.CreatedAt,
		&item.UpdatedAt,
		&item.Targeted,
		&item.Sent,
		&item.Failed,
	); err != nil {
		return item, err
	}
	if len(payloadBytes) > 0 {
		_ = json.Unmarshal(payloadBytes, &item.Payload)
	}
	return item, nil
}

func (r *Repository) FinalizeAdminBroadcast(ctx context.Context, broadcastID int64) (bool, error) {
	row := r.pool.QueryRow(ctx, `
SELECT
	COUNT(*) FILTER (WHERE status IN ('pending', 'processing')) AS remaining,
	COUNT(*) FILTER (WHERE status = 'failed') AS failed
FROM admin_broadcast_jobs
WHERE broadcast_id = $1;`, broadcastID)
	var remaining int
	var failed int
	if err := row.Scan(&remaining, &failed); err != nil {
		return false, err
	}
	if remaining > 0 {
		return false, nil
	}
	status := "done"
	if failed > 0 {
		status = "failed"
	}
	if err := r.UpdateAdminBroadcastStatus(ctx, broadcastID, status); err != nil {
		return false, err
	}
	return true, nil
}
