package repository

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"time"

	"gigme/backend/internal/models"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Repository struct {
	pool *pgxpool.Pool
}

func New(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

func (r *Repository) UpsertUser(ctx context.Context, user models.User) (models.User, error) {
	query := `
INSERT INTO users (telegram_id, username, first_name, last_name, photo_url)
VALUES ($1, $2, $3, $4, $5)
ON CONFLICT (telegram_id) DO UPDATE SET
	username = EXCLUDED.username,
	first_name = EXCLUDED.first_name,
	last_name = EXCLUDED.last_name,
	photo_url = EXCLUDED.photo_url,
	updated_at = now()
RETURNING id, telegram_id, username, first_name, last_name, photo_url, created_at, updated_at;`

	row := r.pool.QueryRow(ctx, query, user.TelegramID, nullString(user.Username), user.FirstName, nullString(user.LastName), nullString(user.PhotoURL))
	var out models.User
	var username sql.NullString
	var lastName sql.NullString
	var photoURL sql.NullString
	err := row.Scan(&out.ID, &out.TelegramID, &username, &out.FirstName, &lastName, &photoURL, &out.CreatedAt, &out.UpdatedAt)
	if username.Valid {
		out.Username = username.String
	}
	if lastName.Valid {
		out.LastName = lastName.String
	}
	if photoURL.Valid {
		out.PhotoURL = photoURL.String
	}
	return out, err
}

func (r *Repository) GetUserByID(ctx context.Context, id int64) (models.User, error) {
	row := r.pool.QueryRow(ctx, `SELECT id, telegram_id, username, first_name, last_name, photo_url, created_at, updated_at FROM users WHERE id = $1`, id)
	var out models.User
	var username sql.NullString
	var lastName sql.NullString
	var photoURL sql.NullString
	err := row.Scan(&out.ID, &out.TelegramID, &username, &out.FirstName, &lastName, &photoURL, &out.CreatedAt, &out.UpdatedAt)
	if username.Valid {
		out.Username = username.String
	}
	if lastName.Valid {
		out.LastName = lastName.String
	}
	if photoURL.Valid {
		out.PhotoURL = photoURL.String
	}
	return out, err
}

func (r *Repository) UpdateUserLocation(ctx context.Context, userID int64, lat, lng float64) error {
	_, err := r.pool.Exec(ctx, `
UPDATE users
SET last_location = ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography,
	last_seen_at = now(),
	updated_at = now()
WHERE id = $1;`, userID, lng, lat)
	return err
}

func (r *Repository) GetNearbyUserIDs(ctx context.Context, lat, lng float64, radiusMeters int, excludeUserID int64, seenAfter *time.Time, limit int) ([]int64, error) {
	query := `
SELECT id
FROM users
WHERE id <> $1
	AND last_location IS NOT NULL
	AND ST_DWithin(last_location, ST_SetSRID(ST_MakePoint($3, $2), 4326)::geography, $4)
	AND (last_seen_at >= $5 OR $5 IS NULL)
ORDER BY last_seen_at DESC`
	args := []interface{}{excludeUserID, lat, lng, radiusMeters, seenAfter}
	if limit > 0 {
		query += `
LIMIT $6;`
		args = append(args, limit)
	} else {
		query += ";"
	}

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]int64, 0)
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		out = append(out, id)
	}
	return out, rows.Err()
}

func (r *Repository) CountUserEventsLastHour(ctx context.Context, userID int64) (int, error) {
	row := r.pool.QueryRow(ctx, `SELECT count(*) FROM events WHERE creator_user_id = $1 AND created_at >= now() - interval '1 hour'`, userID)
	var count int
	if err := row.Scan(&count); err != nil {
		return 0, err
	}
	return count, nil
}

func (r *Repository) CreateEvent(ctx context.Context, event models.Event) (int64, error) {
	filters := event.Filters
	if filters == nil {
		filters = []string{}
	}
	query := `
INSERT INTO events (
	creator_user_id, title, description, starts_at, ends_at, location, address_label, capacity, is_hidden, promoted_until, filters
) VALUES (
	$1, $2, $3, $4, $5,
	ST_SetSRID(ST_MakePoint($6, $7), 4326)::geography,
	$8, $9, $10, $11, $12
) RETURNING id;`

	row := r.pool.QueryRow(ctx, query,
		event.CreatorUserID,
		event.Title,
		event.Description,
		event.StartsAt,
		event.EndsAt,
		event.Lng,
		event.Lat,
		nullString(event.AddressLabel),
		event.Capacity,
		event.IsHidden,
		event.PromotedUntil,
		filters,
	)

	var id int64
	if err := row.Scan(&id); err != nil {
		return 0, err
	}
	return id, nil
}

func (r *Repository) InsertEventMedia(ctx context.Context, eventID int64, urls []string) error {
	if len(urls) == 0 {
		return nil
	}
	batch := &pgx.Batch{}
	for _, url := range urls {
		batch.Queue(`INSERT INTO event_media (event_id, url, type) VALUES ($1, $2, 'image')`, eventID, url)
	}
	br := r.pool.SendBatch(ctx, batch)
	defer br.Close()
	for range urls {
		_, err := br.Exec()
		if err != nil {
			return err
		}
	}
	return nil
}

func (r *Repository) GetEventMarkers(ctx context.Context, from, to *time.Time, lat, lng *float64, radiusMeters int, filters []string) ([]models.EventMarker, error) {
	query := `
SELECT id, title, starts_at,
	ST_Y(location::geometry) AS lat,
	ST_X(location::geometry) AS lng,
	(promoted_until IS NOT NULL AND promoted_until > now()) AS is_promoted,
	filters
FROM events
WHERE is_hidden = false
	AND COALESCE(ends_at, starts_at + interval '2 hours') >= COALESCE($1, now())
	AND (starts_at <= $2 OR $2 IS NULL)`
	args := []interface{}{from, to}
	if lat != nil && lng != nil && radiusMeters > 0 {
		lngIdx := len(args) + 1
		latIdx := len(args) + 2
		radiusIdx := len(args) + 3
		query += fmt.Sprintf(`
	AND ST_DWithin(location, ST_SetSRID(ST_MakePoint($%d, $%d), 4326)::geography, $%d)`, lngIdx, latIdx, radiusIdx)
		args = append(args, *lng, *lat, radiusMeters)
	}
	if len(filters) > 0 {
		filterIdx := len(args) + 1
		query += fmt.Sprintf(`
	AND filters && $%d`, filterIdx)
		args = append(args, filters)
	}
	query += `
ORDER BY
	(promoted_until IS NOT NULL AND promoted_until > now()) DESC,
	starts_at ASC
LIMIT 500;`

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	markers := make([]models.EventMarker, 0)
	for rows.Next() {
		var m models.EventMarker
		if err := rows.Scan(&m.ID, &m.Title, &m.StartsAt, &m.Lat, &m.Lng, &m.IsPromoted, &m.Filters); err != nil {
			return nil, err
		}
		markers = append(markers, m)
	}
	return markers, rows.Err()
}

func (r *Repository) GetFeed(ctx context.Context, limit, offset int, lat, lng *float64, radiusMeters int, filters []string) ([]models.Event, error) {
	query := `
SELECT e.id, e.title, e.description, e.starts_at, e.ends_at,
	ST_Y(e.location::geometry) AS lat,
	ST_X(e.location::geometry) AS lng,
	e.capacity, e.promoted_until, e.filters,
	COALESCE(u.first_name || ' ' || u.last_name, u.first_name) AS creator_name,
	(SELECT url FROM event_media WHERE event_id = e.id ORDER BY id ASC LIMIT 1) AS thumbnail_url,
	(SELECT count(*) FROM event_participants WHERE event_id = e.id) AS participants_count
FROM events e
JOIN users u ON u.id = e.creator_user_id
WHERE e.is_hidden = false
	AND COALESCE(e.ends_at, e.starts_at + interval '2 hours') >= now()`
	args := []interface{}{limit, offset}
	if lat != nil && lng != nil && radiusMeters > 0 {
		lngIdx := len(args) + 1
		latIdx := len(args) + 2
		radiusIdx := len(args) + 3
		query += fmt.Sprintf(`
	AND ST_DWithin(e.location, ST_SetSRID(ST_MakePoint($%d, $%d), 4326)::geography, $%d)`, lngIdx, latIdx, radiusIdx)
		args = append(args, *lng, *lat, radiusMeters)
	}
	if len(filters) > 0 {
		filterIdx := len(args) + 1
		query += fmt.Sprintf(`
	AND e.filters && $%d`, filterIdx)
		args = append(args, filters)
	}
	query += `
ORDER BY
	(e.promoted_until IS NOT NULL AND e.promoted_until > now()) DESC,
	e.starts_at ASC
LIMIT $1 OFFSET $2;`

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]models.Event, 0)
	for rows.Next() {
		var e models.Event
		var thumb sql.NullString
		if err := rows.Scan(&e.ID, &e.Title, &e.Description, &e.StartsAt, &e.EndsAt, &e.Lat, &e.Lng, &e.Capacity, &e.PromotedUntil, &e.Filters, &e.CreatorName, &thumb, &e.Participants); err != nil {
			return nil, err
		}
		if thumb.Valid {
			e.ThumbnailURL = thumb.String
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

func (r *Repository) GetEventByID(ctx context.Context, eventID int64) (models.Event, error) {
	query := `
SELECT e.id, e.creator_user_id, e.title, e.description, e.starts_at, e.ends_at,
	ST_Y(e.location::geometry) AS lat,
	ST_X(e.location::geometry) AS lng,
	e.address_label, e.capacity, e.is_hidden, e.promoted_until, e.filters,
	e.created_at, e.updated_at,
	COALESCE(u.first_name || ' ' || u.last_name, u.first_name) AS creator_name,
	(SELECT count(*) FROM event_participants WHERE event_id = e.id) AS participants_count
FROM events e
JOIN users u ON u.id = e.creator_user_id
WHERE e.id = $1;`

	row := r.pool.QueryRow(ctx, query, eventID)
	var e models.Event
	var address sql.NullString
	if err := row.Scan(&e.ID, &e.CreatorUserID, &e.Title, &e.Description, &e.StartsAt, &e.EndsAt, &e.Lat, &e.Lng, &address, &e.Capacity, &e.IsHidden, &e.PromotedUntil, &e.Filters, &e.CreatedAt, &e.UpdatedAt, &e.CreatorName, &e.Participants); err != nil {
		return models.Event{}, err
	}
	if address.Valid {
		e.AddressLabel = address.String
	}
	return e, nil
}

func (r *Repository) GetParticipantsPreview(ctx context.Context, eventID int64, limit int) ([]models.Participant, error) {
	query := `
SELECT p.user_id, COALESCE(u.first_name || ' ' || u.last_name, u.first_name) AS name, p.joined_at
FROM event_participants p
JOIN users u ON u.id = p.user_id
WHERE p.event_id = $1
ORDER BY p.joined_at ASC
LIMIT $2;`

	rows, err := r.pool.Query(ctx, query, eventID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]models.Participant, 0)
	for rows.Next() {
		var p models.Participant
		if err := rows.Scan(&p.UserID, &p.Name, &p.JoinedAt); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

func (r *Repository) IsUserJoined(ctx context.Context, eventID, userID int64) (bool, error) {
	row := r.pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM event_participants WHERE event_id = $1 AND user_id = $2)`, eventID, userID)
	var exists bool
	if err := row.Scan(&exists); err != nil {
		return false, err
	}
	return exists, nil
}

func (r *Repository) JoinEvent(ctx context.Context, eventID, userID int64) error {
	_, err := r.pool.Exec(ctx, `INSERT INTO event_participants (event_id, user_id, status) VALUES ($1, $2, 'joined') ON CONFLICT DO NOTHING`, eventID, userID)
	return err
}

func (r *Repository) LeaveEvent(ctx context.Context, eventID, userID int64) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM event_participants WHERE event_id = $1 AND user_id = $2`, eventID, userID)
	return err
}

func (r *Repository) CreateNotificationJob(ctx context.Context, job models.NotificationJob) (int64, error) {
	payload, err := json.Marshal(job.Payload)
	if err != nil {
		return 0, err
	}
	row := r.pool.QueryRow(ctx, `
INSERT INTO notification_jobs (user_id, event_id, kind, run_at, payload, status)
VALUES ($1, $2, $3, $4, $5, $6)
RETURNING id;`, job.UserID, job.EventID, job.Kind, job.RunAt, payload, job.Status)
	var id int64
	if err := row.Scan(&id); err != nil {
		return 0, err
	}
	return id, nil
}

func (r *Repository) CreateNotificationJobsForAllUsers(ctx context.Context, eventID int64, kind string, runAt time.Time, payload map[string]interface{}) (int64, error) {
	payloadBytes, err := json.Marshal(payload)
	if err != nil {
		return 0, err
	}
	command, err := r.pool.Exec(ctx, `
INSERT INTO notification_jobs (user_id, event_id, kind, run_at, payload, status)
SELECT id, $1, $2, $3, $4, 'pending'
FROM users;`, eventID, kind, runAt, payloadBytes)
	if err != nil {
		return 0, err
	}
	return command.RowsAffected(), nil
}

func (r *Repository) FetchDueNotificationJobs(ctx context.Context, limit int) ([]models.NotificationJob, error) {
	query := `
WITH cte AS (
	SELECT id
	FROM notification_jobs
	WHERE status = 'pending' AND run_at <= now()
	ORDER BY run_at ASC
	LIMIT $1
	FOR UPDATE SKIP LOCKED
)
UPDATE notification_jobs n
SET status = 'processing', updated_at = now()
FROM cte
WHERE n.id = cte.id
RETURNING n.id, n.user_id, n.event_id, n.kind, n.run_at, n.payload, n.status, n.attempts, COALESCE(n.last_error, '');`

	rows, err := r.pool.Query(ctx, query, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	jobs := make([]models.NotificationJob, 0)
	for rows.Next() {
		var job models.NotificationJob
		var payloadBytes []byte
		var eventID *int64
		if err := rows.Scan(&job.ID, &job.UserID, &eventID, &job.Kind, &job.RunAt, &payloadBytes, &job.Status, &job.Attempts, &job.LastError); err != nil {
			return nil, err
		}
		job.EventID = eventID
		if len(payloadBytes) > 0 {
			_ = json.Unmarshal(payloadBytes, &job.Payload)
		}
		jobs = append(jobs, job)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}
	return jobs, nil
}

func (r *Repository) UpdateNotificationJobStatus(ctx context.Context, jobID int64, status string, attempts int, lastError string, nextRun *time.Time) error {
	query := `UPDATE notification_jobs SET status = $1, attempts = $2, last_error = $3, run_at = COALESCE($4, run_at), updated_at = now() WHERE id = $5`
	_, err := r.pool.Exec(ctx, query, status, attempts, nullString(lastError), nextRun, jobID)
	return err
}

func (r *Repository) RequeueStaleProcessing(ctx context.Context, staleAfter time.Duration) error {
	query := `UPDATE notification_jobs SET status = 'pending', updated_at = now() WHERE status = 'processing' AND updated_at <= now() - $1::interval`
	interval := fmt.Sprintf("%d seconds", int(staleAfter.Seconds()))
	_, err := r.pool.Exec(ctx, query, interval)
	return err
}

func (r *Repository) GetEventStart(ctx context.Context, eventID int64) (time.Time, error) {
	row := r.pool.QueryRow(ctx, `SELECT starts_at FROM events WHERE id = $1`, eventID)
	var t time.Time
	if err := row.Scan(&t); err != nil {
		return time.Time{}, err
	}
	return t, nil
}

func nullString(val string) interface{} {
	if val == "" {
		return nil
	}
	return val
}

func (r *Repository) GetEventTitle(ctx context.Context, eventID int64) (string, error) {
	row := r.pool.QueryRow(ctx, `SELECT title FROM events WHERE id = $1`, eventID)
	var title string
	if err := row.Scan(&title); err != nil {
		return "", err
	}
	return title, nil
}

func (r *Repository) GetUserTelegramID(ctx context.Context, userID int64) (int64, error) {
	row := r.pool.QueryRow(ctx, `SELECT telegram_id FROM users WHERE id = $1`, userID)
	var tid int64
	if err := row.Scan(&tid); err != nil {
		return 0, err
	}
	return tid, nil
}

func (r *Repository) GetEventCapacity(ctx context.Context, eventID int64) (*int, error) {
	row := r.pool.QueryRow(ctx, `SELECT capacity FROM events WHERE id = $1`, eventID)
	var cap *int
	if err := row.Scan(&cap); err != nil {
		return nil, err
	}
	return cap, nil
}

func (r *Repository) CountParticipants(ctx context.Context, eventID int64) (int, error) {
	row := r.pool.QueryRow(ctx, `SELECT count(*) FROM event_participants WHERE event_id = $1`, eventID)
	var count int
	if err := row.Scan(&count); err != nil {
		return 0, err
	}
	return count, nil
}

func (r *Repository) WithTx(ctx context.Context, fn func(pgx.Tx) error) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	if err := fn(tx); err != nil {
		_ = tx.Rollback(ctx)
		return err
	}
	return tx.Commit(ctx)
}

func (r *Repository) CreateEventWithMedia(ctx context.Context, event models.Event, media []string) (int64, error) {
	var eventID int64
	filters := event.Filters
	if filters == nil {
		filters = []string{}
	}
	return eventID, r.WithTx(ctx, func(tx pgx.Tx) error {
		row := tx.QueryRow(ctx, `
INSERT INTO events (
	creator_user_id, title, description, starts_at, ends_at, location, address_label, capacity, is_hidden, promoted_until, filters
) VALUES (
	$1, $2, $3, $4, $5,
	ST_SetSRID(ST_MakePoint($6, $7), 4326)::geography,
	$8, $9, $10, $11, $12
) RETURNING id;`,
			event.CreatorUserID, event.Title, event.Description, event.StartsAt, event.EndsAt, event.Lng, event.Lat, nullString(event.AddressLabel), event.Capacity, event.IsHidden, event.PromotedUntil, filters)
		if err := row.Scan(&eventID); err != nil {
			return err
		}
		for _, url := range media {
			if _, err := tx.Exec(ctx, `INSERT INTO event_media (event_id, url, type) VALUES ($1, $2, 'image')`, eventID, url); err != nil {
				return err
			}
		}
		return nil
	})
}

func (r *Repository) ListEventMedia(ctx context.Context, eventID int64) ([]string, error) {
	rows, err := r.pool.Query(ctx, `SELECT url FROM event_media WHERE event_id = $1 ORDER BY id ASC`, eventID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]string, 0)
	for rows.Next() {
		var url string
		if err := rows.Scan(&url); err != nil {
			return nil, err
		}
		out = append(out, url)
	}
	return out, rows.Err()
}

func (r *Repository) SetEventHidden(ctx context.Context, eventID int64, hidden bool) error {
	_, err := r.pool.Exec(ctx, `UPDATE events SET is_hidden = $1, updated_at = now() WHERE id = $2`, hidden, eventID)
	return err
}

func (r *Repository) ensurePool() error {
	if r.pool == nil {
		return fmt.Errorf("db pool is nil")
	}
	return nil
}
