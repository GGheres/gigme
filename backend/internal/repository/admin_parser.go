package repository

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"time"

	"gigme/backend/internal/models"

	"github.com/jackc/pgx/v5"
)

// CreateAdminParserSource creates a new parser source configuration for admins.
func (r *Repository) CreateAdminParserSource(ctx context.Context, createdBy int64, sourceType, input, title string, isActive bool) (models.AdminParserSource, error) {
	row := r.pool.QueryRow(ctx, `
INSERT INTO admin_event_parser_sources (source_type, input, title, is_active, created_by)
VALUES ($1, $2, $3, $4, $5)
RETURNING id, source_type, input, title, is_active, last_parsed_at, created_by, created_at, updated_at;`,
		sourceType,
		input,
		nullString(title),
		isActive,
		createdBy,
	)
	return scanAdminParserSource(row)
}

// ListAdminParserSources returns parser sources ordered by creation time with total count.
func (r *Repository) ListAdminParserSources(ctx context.Context, limit, offset int) ([]models.AdminParserSource, int, error) {
	rows, err := r.pool.Query(ctx, `
SELECT id, source_type, input, title, is_active, last_parsed_at, created_by, created_at, updated_at,
	COUNT(*) OVER() AS total
FROM admin_event_parser_sources
ORDER BY created_at DESC
LIMIT $1 OFFSET $2;`, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	items := make([]models.AdminParserSource, 0)
	total := 0
	for rows.Next() {
		var item models.AdminParserSource
		var title sql.NullString
		var lastParsedAt sql.NullTime
		var rowTotal int
		if err := rows.Scan(
			&item.ID,
			&item.SourceType,
			&item.Input,
			&title,
			&item.IsActive,
			&lastParsedAt,
			&item.CreatedBy,
			&item.CreatedAt,
			&item.UpdatedAt,
			&rowTotal,
		); err != nil {
			return nil, 0, err
		}
		if title.Valid {
			item.Title = title.String
		}
		if lastParsedAt.Valid {
			val := lastParsedAt.Time
			item.LastParsedAt = &val
		}
		total = rowTotal
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, err
	}
	return items, total, nil
}

// GetAdminParserSource loads a parser source by its identifier.
func (r *Repository) GetAdminParserSource(ctx context.Context, id int64) (models.AdminParserSource, error) {
	row := r.pool.QueryRow(ctx, `
SELECT id, source_type, input, title, is_active, last_parsed_at, created_by, created_at, updated_at
FROM admin_event_parser_sources
WHERE id = $1;`, id)
	return scanAdminParserSource(row)
}

// SetAdminParserSourceActive toggles the active flag for a parser source.
func (r *Repository) SetAdminParserSourceActive(ctx context.Context, id int64, active bool) error {
	cmd, err := r.pool.Exec(ctx, `
UPDATE admin_event_parser_sources
SET is_active = $1, updated_at = now()
WHERE id = $2;`, active, id)
	if err != nil {
		return err
	}
	if cmd.RowsAffected() == 0 {
		return pgx.ErrNoRows
	}
	return nil
}

// TouchAdminParserSourceParsed updates parser source timestamps after a successful parse run.
func (r *Repository) TouchAdminParserSourceParsed(ctx context.Context, id int64) error {
	cmd, err := r.pool.Exec(ctx, `
UPDATE admin_event_parser_sources
SET last_parsed_at = now(), updated_at = now()
WHERE id = $1;`, id)
	if err != nil {
		return err
	}
	if cmd.RowsAffected() == 0 {
		return pgx.ErrNoRows
	}
	return nil
}

// CreateAdminParsedEvent stores a parsed event candidate produced by a parser run.
func (r *Repository) CreateAdminParsedEvent(
	ctx context.Context,
	sourceID *int64,
	sourceType,
	input,
	name string,
	dateTime *time.Time,
	location,
	description string,
	links []string,
	status,
	parserError string,
) (models.AdminParsedEvent, error) {
	if links == nil {
		links = []string{}
	}
	row := r.pool.QueryRow(ctx, `
INSERT INTO admin_event_parser_events (
	source_id, source_type, input, name, date_time, location, description, links, status, parser_error, parsed_at
) VALUES (
	$1, $2, $3, $4, $5, $6, $7, $8, $9, $10, now()
)
RETURNING id, source_id, source_type, input, name, date_time, location, description, links,
	status, parser_error, parsed_at, imported_event_id, imported_by, imported_at, created_at, updated_at;`,
		sourceID,
		sourceType,
		input,
		name,
		dateTime,
		location,
		description,
		links,
		status,
		nullString(parserError),
	)
	return scanAdminParsedEvent(row)
}

// ListAdminParsedEvents returns parsed events with optional status/source filters and total count.
func (r *Repository) ListAdminParsedEvents(ctx context.Context, status string, sourceID *int64, limit, offset int) ([]models.AdminParsedEvent, int, error) {
	clauses := make([]string, 0)
	args := make([]interface{}, 0)
	idx := 1
	if strings.TrimSpace(status) != "" {
		clauses = append(clauses, fmt.Sprintf("status = $%d", idx))
		args = append(args, status)
		idx++
	}
	if sourceID != nil {
		clauses = append(clauses, fmt.Sprintf("source_id = $%d", idx))
		args = append(args, *sourceID)
		idx++
	}
	query := `
SELECT id, source_id, source_type, input, name, date_time, location, description, links,
	status, parser_error, parsed_at, imported_event_id, imported_by, imported_at, created_at, updated_at,
	COUNT(*) OVER() AS total
FROM admin_event_parser_events`
	if len(clauses) > 0 {
		query += " WHERE " + strings.Join(clauses, " AND ")
	}
	query += fmt.Sprintf(" ORDER BY parsed_at DESC LIMIT $%d OFFSET $%d", idx, idx+1)
	args = append(args, limit, offset)

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	items := make([]models.AdminParsedEvent, 0)
	total := 0
	for rows.Next() {
		item, rowTotal, err := scanAdminParsedEventWithTotal(rows)
		if err != nil {
			return nil, 0, err
		}
		total = rowTotal
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, err
	}
	return items, total, nil
}

// GetAdminParsedEvent fetches a parsed event candidate by id.
func (r *Repository) GetAdminParsedEvent(ctx context.Context, id int64) (models.AdminParsedEvent, error) {
	row := r.pool.QueryRow(ctx, `
SELECT id, source_id, source_type, input, name, date_time, location, description, links,
	status, parser_error, parsed_at, imported_event_id, imported_by, imported_at, created_at, updated_at
FROM admin_event_parser_events
WHERE id = $1;`, id)
	return scanAdminParsedEvent(row)
}

// RejectAdminParsedEvent marks a parsed event as rejected when it has not been imported yet.
func (r *Repository) RejectAdminParsedEvent(ctx context.Context, id int64) error {
	cmd, err := r.pool.Exec(ctx, `
UPDATE admin_event_parser_events
SET status = 'rejected', updated_at = now()
WHERE id = $1 AND status <> 'imported';`, id)
	if err != nil {
		return err
	}
	if cmd.RowsAffected() == 0 {
		return pgx.ErrNoRows
	}
	return nil
}

// DeleteAdminParsedEvent permanently removes a parsed event candidate.
func (r *Repository) DeleteAdminParsedEvent(ctx context.Context, id int64) error {
	cmd, err := r.pool.Exec(ctx, `DELETE FROM admin_event_parser_events WHERE id = $1`, id)
	if err != nil {
		return err
	}
	if cmd.RowsAffected() == 0 {
		return pgx.ErrNoRows
	}
	return nil
}

// ImportAdminParsedEvent creates a real event from parsed data and marks the parsed row as imported.
func (r *Repository) ImportAdminParsedEvent(ctx context.Context, parsedEventID, importedBy int64, event models.Event, media []string) (int64, error) {
	var eventID int64
	filters := event.Filters
	if filters == nil {
		filters = []string{}
	}
	links := event.Links
	if links == nil {
		links = []string{}
	}
	err := r.WithTx(ctx, func(tx pgx.Tx) error {
		var status string
		if err := tx.QueryRow(ctx, `SELECT status FROM admin_event_parser_events WHERE id = $1 FOR UPDATE`, parsedEventID).Scan(&status); err != nil {
			return err
		}
		if status == "imported" {
			return fmt.Errorf("parsed event already imported")
		}

		row := tx.QueryRow(ctx, `
INSERT INTO events (
	creator_user_id, title, description, starts_at, ends_at, location, address_label,
	contact_telegram, contact_whatsapp, contact_wechat, contact_fb_messenger, contact_snapchat,
	capacity, is_hidden, is_private, access_key, promoted_until, filters, links
) VALUES (
	$1, $2, $3, $4, $5,
	ST_SetSRID(ST_MakePoint($6, $7), 4326)::geography,
	$8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20
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
			links,
		)
		if err := row.Scan(&eventID); err != nil {
			return err
		}
		for _, mediaURL := range media {
			if strings.TrimSpace(mediaURL) == "" {
				continue
			}
			if _, err := tx.Exec(ctx, `INSERT INTO event_media (event_id, url, type) VALUES ($1, $2, 'image')`, eventID, mediaURL); err != nil {
				return err
			}
		}
		if _, err := tx.Exec(ctx, `
UPDATE admin_event_parser_events
SET status = 'imported', imported_event_id = $2, imported_by = $3, imported_at = now(), updated_at = now()
WHERE id = $1;`, parsedEventID, eventID, importedBy); err != nil {
			return err
		}
		return nil
	})
	return eventID, err
}

// scanAdminParserSource maps a parser source row into the domain model.
func scanAdminParserSource(row pgx.Row) (models.AdminParserSource, error) {
	var item models.AdminParserSource
	var title sql.NullString
	var lastParsedAt sql.NullTime
	if err := row.Scan(
		&item.ID,
		&item.SourceType,
		&item.Input,
		&title,
		&item.IsActive,
		&lastParsedAt,
		&item.CreatedBy,
		&item.CreatedAt,
		&item.UpdatedAt,
	); err != nil {
		return item, err
	}
	if title.Valid {
		item.Title = title.String
	}
	if lastParsedAt.Valid {
		val := lastParsedAt.Time
		item.LastParsedAt = &val
	}
	return item, nil
}

// scanAdminParsedEvent maps a parsed event row into the domain model.
func scanAdminParsedEvent(row pgx.Row) (models.AdminParsedEvent, error) {
	var item models.AdminParsedEvent
	var sourceID sql.NullInt64
	var dateTime sql.NullTime
	var parserError sql.NullString
	var importedEventID sql.NullInt64
	var importedBy sql.NullInt64
	var importedAt sql.NullTime
	if err := row.Scan(
		&item.ID,
		&sourceID,
		&item.SourceType,
		&item.Input,
		&item.Name,
		&dateTime,
		&item.Location,
		&item.Description,
		&item.Links,
		&item.Status,
		&parserError,
		&item.ParsedAt,
		&importedEventID,
		&importedBy,
		&importedAt,
		&item.CreatedAt,
		&item.UpdatedAt,
	); err != nil {
		return item, err
	}
	if sourceID.Valid {
		val := sourceID.Int64
		item.SourceID = &val
	}
	if dateTime.Valid {
		val := dateTime.Time
		item.DateTime = &val
	}
	if parserError.Valid {
		item.ParserError = parserError.String
	}
	if importedEventID.Valid {
		val := importedEventID.Int64
		item.ImportedEventID = &val
	}
	if importedBy.Valid {
		val := importedBy.Int64
		item.ImportedBy = &val
	}
	if importedAt.Valid {
		val := importedAt.Time
		item.ImportedAt = &val
	}
	return item, nil
}

// scanAdminParsedEventWithTotal maps a parsed event row and extracts window total from the same row.
func scanAdminParsedEventWithTotal(rows pgx.Rows) (models.AdminParsedEvent, int, error) {
	var item models.AdminParsedEvent
	var sourceID sql.NullInt64
	var dateTime sql.NullTime
	var parserError sql.NullString
	var importedEventID sql.NullInt64
	var importedBy sql.NullInt64
	var importedAt sql.NullTime
	var total int
	if err := rows.Scan(
		&item.ID,
		&sourceID,
		&item.SourceType,
		&item.Input,
		&item.Name,
		&dateTime,
		&item.Location,
		&item.Description,
		&item.Links,
		&item.Status,
		&parserError,
		&item.ParsedAt,
		&importedEventID,
		&importedBy,
		&importedAt,
		&item.CreatedAt,
		&item.UpdatedAt,
		&total,
	); err != nil {
		return item, 0, err
	}
	if sourceID.Valid {
		val := sourceID.Int64
		item.SourceID = &val
	}
	if dateTime.Valid {
		val := dateTime.Time
		item.DateTime = &val
	}
	if parserError.Valid {
		item.ParserError = parserError.String
	}
	if importedEventID.Valid {
		val := importedEventID.Int64
		item.ImportedEventID = &val
	}
	if importedBy.Valid {
		val := importedBy.Int64
		item.ImportedBy = &val
	}
	if importedAt.Valid {
		val := importedAt.Time
		item.ImportedAt = &val
	}
	return item, total, nil
}
