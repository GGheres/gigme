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
RETURNING id, telegram_id, username, first_name, last_name, photo_url, rating, rating_count, balance_tokens, created_at, updated_at;`

	row := r.pool.QueryRow(ctx, query, user.TelegramID, nullString(user.Username), user.FirstName, nullString(user.LastName), nullString(user.PhotoURL))
	var out models.User
	var username sql.NullString
	var lastName sql.NullString
	var photoURL sql.NullString
	err := row.Scan(&out.ID, &out.TelegramID, &username, &out.FirstName, &lastName, &photoURL, &out.Rating, &out.RatingCount, &out.BalanceTokens, &out.CreatedAt, &out.UpdatedAt)
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
	row := r.pool.QueryRow(ctx, `SELECT id, telegram_id, username, first_name, last_name, photo_url, rating, rating_count, balance_tokens, created_at, updated_at FROM users WHERE id = $1`, id)
	var out models.User
	var username sql.NullString
	var lastName sql.NullString
	var photoURL sql.NullString
	err := row.Scan(&out.ID, &out.TelegramID, &username, &out.FirstName, &lastName, &photoURL, &out.Rating, &out.RatingCount, &out.BalanceTokens, &out.CreatedAt, &out.UpdatedAt)
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

func (r *Repository) AddUserTokens(ctx context.Context, userID int64, amount int64) (int64, error) {
	row := r.pool.QueryRow(ctx, `
UPDATE users
SET balance_tokens = balance_tokens + $2,
	updated_at = now()
WHERE id = $1
RETURNING balance_tokens;`, userID, amount)
	var balance int64
	if err := row.Scan(&balance); err != nil {
		return 0, err
	}
	return balance, nil
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
	creator_user_id, title, description, starts_at, ends_at, location, address_label,
	contact_telegram, contact_whatsapp, contact_wechat, contact_fb_messenger, contact_snapchat,
	capacity, is_hidden, is_private, access_key, promoted_until, filters
) VALUES (
	$1, $2, $3, $4, $5,
	ST_SetSRID(ST_MakePoint($6, $7), 4326)::geography,
	$8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19
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
		nullString(event.ContactTelegram),
		nullString(event.ContactWhatsapp),
		nullString(event.ContactWechat),
		nullString(event.ContactFbMessenger),
		nullString(event.ContactSnapchat),
		event.Capacity,
		event.IsHidden,
		event.IsPrivate,
		nullString(event.AccessKey),
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

func (r *Repository) GetEventMarkers(ctx context.Context, userID int64, from, to *time.Time, lat, lng *float64, radiusMeters int, filters []string, accessKeys []string) ([]models.EventMarker, error) {
	query := `
SELECT e.id, e.title, e.starts_at,
	ST_Y(e.location::geometry) AS lat,
	ST_X(e.location::geometry) AS lng,
	(e.promoted_until IS NOT NULL AND e.promoted_until > now()) AS is_promoted,
	e.filters
FROM events e
LEFT JOIN event_participants ep ON ep.event_id = e.id AND ep.user_id = $1
WHERE e.is_hidden = false
	AND COALESCE(e.ends_at, e.starts_at + interval '2 hours') >= COALESCE($2, now())
	AND (e.starts_at <= $3 OR $3 IS NULL)`
	args := []interface{}{userID, from, to}
	privacy := "e.is_private = false OR e.creator_user_id = $1 OR ep.user_id IS NOT NULL"
	if len(accessKeys) > 0 {
		keyIdx := len(args) + 1
		privacy = fmt.Sprintf("%s OR e.access_key = ANY($%d)", privacy, keyIdx)
		args = append(args, accessKeys)
	}
	query += fmt.Sprintf(`
	AND (%s)`, privacy)
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

func (r *Repository) GetFeed(ctx context.Context, userID int64, limit, offset int, lat, lng *float64, radiusMeters int, filters []string, accessKeys []string) ([]models.Event, error) {
	query := `
SELECT e.id, e.title, e.description, e.starts_at, e.ends_at,
	ST_Y(e.location::geometry) AS lat,
	ST_X(e.location::geometry) AS lng,
	e.capacity, e.promoted_until, e.filters, e.is_private,
	e.contact_telegram, e.contact_whatsapp, e.contact_wechat, e.contact_fb_messenger, e.contact_snapchat,
	COALESCE(u.first_name || ' ' || u.last_name, u.first_name) AS creator_name,
	(SELECT url FROM event_media WHERE event_id = e.id ORDER BY id ASC LIMIT 1) AS thumbnail_url,
	(SELECT count(*) FROM event_participants WHERE event_id = e.id) AS participants_count,
	(SELECT count(*) FROM event_likes WHERE event_id = e.id) AS likes_count,
	(SELECT count(*) FROM event_comments WHERE event_id = e.id) AS comments_count,
	(ep.user_id IS NOT NULL) AS is_joined,
	(SELECT EXISTS(SELECT 1 FROM event_likes WHERE event_id = e.id AND user_id = $1)) AS is_liked
FROM events e
JOIN users u ON u.id = e.creator_user_id
LEFT JOIN event_participants ep ON ep.event_id = e.id AND ep.user_id = $1
WHERE e.is_hidden = false
	AND COALESCE(e.ends_at, e.starts_at + interval '2 hours') >= now()`
	args := []interface{}{userID, limit, offset}
	privacy := "e.is_private = false OR e.creator_user_id = $1 OR ep.user_id IS NOT NULL"
	if len(accessKeys) > 0 {
		keyIdx := len(args) + 1
		privacy = fmt.Sprintf("%s OR e.access_key = ANY($%d)", privacy, keyIdx)
		args = append(args, accessKeys)
	}
	query += fmt.Sprintf(`
	AND (%s)`, privacy)
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
LIMIT $2 OFFSET $3;`

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]models.Event, 0)
	for rows.Next() {
		var e models.Event
		var thumb sql.NullString
		var contactTelegram sql.NullString
		var contactWhatsapp sql.NullString
		var contactWechat sql.NullString
		var contactFbMessenger sql.NullString
		var contactSnapchat sql.NullString
		if err := rows.Scan(
			&e.ID,
			&e.Title,
			&e.Description,
			&e.StartsAt,
			&e.EndsAt,
			&e.Lat,
			&e.Lng,
			&e.Capacity,
			&e.PromotedUntil,
			&e.Filters,
			&e.IsPrivate,
			&contactTelegram,
			&contactWhatsapp,
			&contactWechat,
			&contactFbMessenger,
			&contactSnapchat,
			&e.CreatorName,
			&thumb,
			&e.Participants,
			&e.LikesCount,
			&e.CommentsCount,
			&e.IsJoined,
			&e.IsLiked,
		); err != nil {
			return nil, err
		}
		if contactTelegram.Valid {
			e.ContactTelegram = contactTelegram.String
		}
		if contactWhatsapp.Valid {
			e.ContactWhatsapp = contactWhatsapp.String
		}
		if contactWechat.Valid {
			e.ContactWechat = contactWechat.String
		}
		if contactFbMessenger.Valid {
			e.ContactFbMessenger = contactFbMessenger.String
		}
		if contactSnapchat.Valid {
			e.ContactSnapchat = contactSnapchat.String
		}
		if thumb.Valid {
			e.ThumbnailURL = thumb.String
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

func (r *Repository) ListUserEvents(ctx context.Context, userID int64, limit, offset int) ([]models.UserEvent, int, error) {
	rows, err := r.pool.Query(ctx, `
SELECT e.id, e.title, e.starts_at,
	(SELECT count(*) FROM event_participants WHERE event_id = e.id) AS participants_count,
	(SELECT url FROM event_media WHERE event_id = e.id ORDER BY id ASC LIMIT 1) AS thumbnail_url,
	COUNT(*) OVER() AS total
FROM events e
WHERE e.creator_user_id = $1
ORDER BY e.starts_at DESC
LIMIT $2 OFFSET $3;`, userID, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	out := make([]models.UserEvent, 0)
	total := 0
	for rows.Next() {
		var item models.UserEvent
		var thumb sql.NullString
		var rowTotal int
		if err := rows.Scan(&item.ID, &item.Title, &item.StartsAt, &item.ParticipantsCount, &thumb, &rowTotal); err != nil {
			return nil, 0, err
		}
		if thumb.Valid {
			item.ThumbnailURL = thumb.String
		}
		total = rowTotal
		out = append(out, item)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, err
	}
	return out, total, nil
}

func (r *Repository) GetEventByID(ctx context.Context, eventID int64) (models.Event, error) {
	query := `
SELECT e.id, e.creator_user_id, e.title, e.description, e.starts_at, e.ends_at,
	ST_Y(e.location::geometry) AS lat,
	ST_X(e.location::geometry) AS lng,
	e.address_label,
	e.contact_telegram, e.contact_whatsapp, e.contact_wechat, e.contact_fb_messenger, e.contact_snapchat,
	e.capacity, e.is_hidden, e.is_private, e.access_key, e.promoted_until, e.filters,
	e.created_at, e.updated_at,
	COALESCE(u.first_name || ' ' || u.last_name, u.first_name) AS creator_name,
	(SELECT count(*) FROM event_participants WHERE event_id = e.id) AS participants_count,
	(SELECT count(*) FROM event_likes WHERE event_id = e.id) AS likes_count,
	(SELECT count(*) FROM event_comments WHERE event_id = e.id) AS comments_count
FROM events e
JOIN users u ON u.id = e.creator_user_id
WHERE e.id = $1;`

	row := r.pool.QueryRow(ctx, query, eventID)
	var e models.Event
	var address sql.NullString
	var contactTelegram sql.NullString
	var contactWhatsapp sql.NullString
	var contactWechat sql.NullString
	var contactFbMessenger sql.NullString
	var contactSnapchat sql.NullString
	var accessKey sql.NullString
	if err := row.Scan(
		&e.ID,
		&e.CreatorUserID,
		&e.Title,
		&e.Description,
		&e.StartsAt,
		&e.EndsAt,
		&e.Lat,
		&e.Lng,
		&address,
		&contactTelegram,
		&contactWhatsapp,
		&contactWechat,
		&contactFbMessenger,
		&contactSnapchat,
		&e.Capacity,
		&e.IsHidden,
		&e.IsPrivate,
		&accessKey,
		&e.PromotedUntil,
		&e.Filters,
		&e.CreatedAt,
		&e.UpdatedAt,
		&e.CreatorName,
		&e.Participants,
		&e.LikesCount,
		&e.CommentsCount,
	); err != nil {
		return models.Event{}, err
	}
	if address.Valid {
		e.AddressLabel = address.String
	}
	if contactTelegram.Valid {
		e.ContactTelegram = contactTelegram.String
	}
	if contactWhatsapp.Valid {
		e.ContactWhatsapp = contactWhatsapp.String
	}
	if contactWechat.Valid {
		e.ContactWechat = contactWechat.String
	}
	if contactFbMessenger.Valid {
		e.ContactFbMessenger = contactFbMessenger.String
	}
	if contactSnapchat.Valid {
		e.ContactSnapchat = contactSnapchat.String
	}
	if accessKey.Valid {
		e.AccessKey = accessKey.String
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

func (r *Repository) LikeEvent(ctx context.Context, eventID, userID int64) error {
	_, err := r.pool.Exec(ctx, `INSERT INTO event_likes (event_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`, eventID, userID)
	return err
}

func (r *Repository) UnlikeEvent(ctx context.Context, eventID, userID int64) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM event_likes WHERE event_id = $1 AND user_id = $2`, eventID, userID)
	return err
}

func (r *Repository) IsEventLiked(ctx context.Context, eventID, userID int64) (bool, error) {
	row := r.pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM event_likes WHERE event_id = $1 AND user_id = $2)`, eventID, userID)
	var exists bool
	if err := row.Scan(&exists); err != nil {
		return false, err
	}
	return exists, nil
}

func (r *Repository) CountEventLikes(ctx context.Context, eventID int64) (int, error) {
	row := r.pool.QueryRow(ctx, `SELECT count(*) FROM event_likes WHERE event_id = $1`, eventID)
	var count int
	if err := row.Scan(&count); err != nil {
		return 0, err
	}
	return count, nil
}

func (r *Repository) CountEventComments(ctx context.Context, eventID int64) (int, error) {
	row := r.pool.QueryRow(ctx, `SELECT count(*) FROM event_comments WHERE event_id = $1`, eventID)
	var count int
	if err := row.Scan(&count); err != nil {
		return 0, err
	}
	return count, nil
}

func (r *Repository) AddEventComment(ctx context.Context, eventID, userID int64, body string) (models.EventComment, error) {
	query := `
WITH inserted AS (
	INSERT INTO event_comments (event_id, user_id, body)
	VALUES ($1, $2, $3)
	RETURNING id, event_id, user_id, body, created_at
)
SELECT inserted.id, inserted.event_id, inserted.user_id, inserted.body, inserted.created_at,
	COALESCE(u.first_name || ' ' || u.last_name, u.first_name) AS user_name
FROM inserted
JOIN users u ON u.id = inserted.user_id;`
	row := r.pool.QueryRow(ctx, query, eventID, userID, body)
	var comment models.EventComment
	if err := row.Scan(&comment.ID, &comment.EventID, &comment.UserID, &comment.Body, &comment.CreatedAt, &comment.UserName); err != nil {
		return models.EventComment{}, err
	}
	return comment, nil
}

func (r *Repository) ListEventComments(ctx context.Context, eventID int64, limit, offset int) ([]models.EventComment, error) {
	rows, err := r.pool.Query(ctx, `
SELECT c.id, c.event_id, c.user_id, c.body, c.created_at,
	COALESCE(u.first_name || ' ' || u.last_name, u.first_name) AS user_name
FROM event_comments c
JOIN users u ON u.id = c.user_id
WHERE c.event_id = $1
ORDER BY c.created_at ASC
LIMIT $2 OFFSET $3;`, eventID, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	comments := make([]models.EventComment, 0)
	for rows.Next() {
		var comment models.EventComment
		if err := rows.Scan(&comment.ID, &comment.EventID, &comment.UserID, &comment.Body, &comment.CreatedAt, &comment.UserName); err != nil {
			return nil, err
		}
		comments = append(comments, comment)
	}
	return comments, rows.Err()
}

func (r *Repository) GetEventCreatorUserID(ctx context.Context, eventID int64) (int64, error) {
	row := r.pool.QueryRow(ctx, `SELECT creator_user_id FROM events WHERE id = $1`, eventID)
	var userID int64
	if err := row.Scan(&userID); err != nil {
		return 0, err
	}
	return userID, nil
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
	creator_user_id, title, description, starts_at, ends_at, location, address_label,
	contact_telegram, contact_whatsapp, contact_wechat, contact_fb_messenger, contact_snapchat,
	capacity, is_hidden, is_private, access_key, promoted_until, filters
) VALUES (
	$1, $2, $3, $4, $5,
	ST_SetSRID(ST_MakePoint($6, $7), 4326)::geography,
	$8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19
) RETURNING id;`,
			event.CreatorUserID,
			event.Title,
			event.Description,
			event.StartsAt,
			event.EndsAt,
			event.Lng,
			event.Lat,
			nullString(event.AddressLabel),
			nullString(event.ContactTelegram),
			nullString(event.ContactWhatsapp),
			nullString(event.ContactWechat),
			nullString(event.ContactFbMessenger),
			nullString(event.ContactSnapchat),
			event.Capacity,
			event.IsHidden,
			event.IsPrivate,
			nullString(event.AccessKey),
			event.PromotedUntil,
			filters,
		)
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

func (r *Repository) UpdateEventWithMedia(ctx context.Context, event models.Event, media []string, replaceMedia bool) error {
	filters := event.Filters
	if filters == nil {
		filters = []string{}
	}
	return r.WithTx(ctx, func(tx pgx.Tx) error {
		command, err := tx.Exec(ctx, `
UPDATE events SET
	title = $1,
	description = $2,
	starts_at = $3,
	ends_at = $4,
	location = ST_SetSRID(ST_MakePoint($5, $6), 4326)::geography,
	address_label = $7,
	contact_telegram = $8,
	contact_whatsapp = $9,
	contact_wechat = $10,
	contact_fb_messenger = $11,
	contact_snapchat = $12,
	capacity = $13,
	filters = $14,
	updated_at = now()
WHERE id = $15;`,
			event.Title,
			event.Description,
			event.StartsAt,
			event.EndsAt,
			event.Lng,
			event.Lat,
			nullString(event.AddressLabel),
			nullString(event.ContactTelegram),
			nullString(event.ContactWhatsapp),
			nullString(event.ContactWechat),
			nullString(event.ContactFbMessenger),
			nullString(event.ContactSnapchat),
			event.Capacity,
			filters,
			event.ID,
		)
		if err != nil {
			return err
		}
		if command.RowsAffected() == 0 {
			return pgx.ErrNoRows
		}
		if !replaceMedia {
			return nil
		}
		if _, err := tx.Exec(ctx, `DELETE FROM event_media WHERE event_id = $1`, event.ID); err != nil {
			return err
		}
		for _, url := range media {
			if _, err := tx.Exec(ctx, `INSERT INTO event_media (event_id, url, type) VALUES ($1, $2, 'image')`, event.ID, url); err != nil {
				return err
			}
		}
		return nil
	})
}

func (r *Repository) SetEventPromotedUntil(ctx context.Context, eventID int64, until *time.Time) error {
	command, err := r.pool.Exec(ctx, `UPDATE events SET promoted_until = $1, updated_at = now() WHERE id = $2`, until, eventID)
	if err != nil {
		return err
	}
	if command.RowsAffected() == 0 {
		return pgx.ErrNoRows
	}
	return nil
}

func (r *Repository) DeleteEvent(ctx context.Context, eventID int64) error {
	command, err := r.pool.Exec(ctx, `DELETE FROM events WHERE id = $1`, eventID)
	if err != nil {
		return err
	}
	if command.RowsAffected() == 0 {
		return pgx.ErrNoRows
	}
	return nil
}

func (r *Repository) ensurePool() error {
	if r.pool == nil {
		return fmt.Errorf("db pool is nil")
	}
	return nil
}
