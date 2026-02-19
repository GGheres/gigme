package repository

import (
	"context"
	"database/sql"
	"fmt"
	"strings"

	"gigme/backend/internal/models"
)

const (
	adminBotMessageDirectionIncoming = "INCOMING"
	adminBotMessageDirectionOutgoing = "OUTGOING"
)

func (r *Repository) StoreAdminBotIncomingMessage(
	ctx context.Context,
	chatID int64,
	telegramMessageID int64,
	senderTelegramID int64,
	senderUsername string,
	senderFirstName string,
	senderLastName string,
	text string,
) error {
	if chatID <= 0 {
		return fmt.Errorf("chat id is required")
	}

	_, err := r.pool.Exec(ctx, `
INSERT INTO admin_bot_messages (
	chat_id,
	direction,
	message_text,
	telegram_message_id,
	sender_telegram_id,
	sender_username,
	sender_first_name,
	sender_last_name,
	admin_telegram_id
)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NULL);`,
		chatID,
		adminBotMessageDirectionIncoming,
		sanitizeAdminBotMessageText(text),
		nullInt64(telegramMessageID),
		nullInt64(senderTelegramID),
		nullString(strings.TrimSpace(senderUsername)),
		nullString(strings.TrimSpace(senderFirstName)),
		nullString(strings.TrimSpace(senderLastName)),
	)
	return err
}

func (r *Repository) StoreAdminBotOutgoingMessage(
	ctx context.Context,
	chatID int64,
	adminTelegramID int64,
	text string,
) error {
	if chatID <= 0 {
		return fmt.Errorf("chat id is required")
	}

	_, err := r.pool.Exec(ctx, `
INSERT INTO admin_bot_messages (
	chat_id,
	direction,
	message_text,
	telegram_message_id,
	sender_telegram_id,
	sender_username,
	sender_first_name,
	sender_last_name,
	admin_telegram_id
)
VALUES ($1, $2, $3, NULL, NULL, NULL, NULL, NULL, $4);`,
		chatID,
		adminBotMessageDirectionOutgoing,
		sanitizeAdminBotMessageText(text),
		nullInt64(adminTelegramID),
	)
	return err
}

func (r *Repository) ListAdminBotMessages(ctx context.Context, chatID *int64, limit, offset int) ([]models.AdminBotMessage, int, error) {
	if limit <= 0 {
		limit = 100
	}
	if limit > 200 {
		limit = 200
	}
	if offset < 0 {
		offset = 0
	}

	var total int
	if err := r.pool.QueryRow(ctx, `
SELECT count(*)
FROM admin_bot_messages m
WHERE ($1::bigint IS NULL OR m.chat_id = $1);`, nullInt64Ptr(chatID)).Scan(&total); err != nil {
		return nil, 0, err
	}

	rows, err := r.pool.Query(ctx, `
SELECT
	m.id,
	m.chat_id,
	m.direction,
	m.message_text,
	m.telegram_message_id,
	m.sender_telegram_id,
	m.sender_username,
	m.sender_first_name,
	m.sender_last_name,
	m.admin_telegram_id,
	m.created_at,
	u.id,
	u.username,
	u.first_name,
	u.last_name
FROM admin_bot_messages m
LEFT JOIN users u ON u.telegram_id = m.chat_id
WHERE ($1::bigint IS NULL OR m.chat_id = $1)
ORDER BY m.created_at DESC, m.id DESC
LIMIT $2 OFFSET $3;`, nullInt64Ptr(chatID), limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	items := make([]models.AdminBotMessage, 0)
	for rows.Next() {
		var item models.AdminBotMessage
		var telegramMessageID sql.NullInt64
		var senderTelegramID sql.NullInt64
		var senderUsername sql.NullString
		var senderFirstName sql.NullString
		var senderLastName sql.NullString
		var adminTelegramID sql.NullInt64
		var userID sql.NullInt64
		var userUsername sql.NullString
		var userFirstName sql.NullString
		var userLastName sql.NullString

		if err := rows.Scan(
			&item.ID,
			&item.ChatID,
			&item.Direction,
			&item.Text,
			&telegramMessageID,
			&senderTelegramID,
			&senderUsername,
			&senderFirstName,
			&senderLastName,
			&adminTelegramID,
			&item.CreatedAt,
			&userID,
			&userUsername,
			&userFirstName,
			&userLastName,
		); err != nil {
			return nil, 0, err
		}

		item.TelegramMessageID = nullInt64ToPtr(telegramMessageID)
		item.SenderTelegramID = nullInt64ToPtr(senderTelegramID)
		item.AdminTelegramID = nullInt64ToPtr(adminTelegramID)
		item.UserID = nullInt64ToPtr(userID)
		if senderUsername.Valid {
			item.SenderUsername = senderUsername.String
		}
		if senderFirstName.Valid {
			item.SenderFirstName = senderFirstName.String
		}
		if senderLastName.Valid {
			item.SenderLastName = senderLastName.String
		}
		if userUsername.Valid {
			item.UserUsername = userUsername.String
		}
		if userFirstName.Valid {
			item.UserFirstName = userFirstName.String
		}
		if userLastName.Valid {
			item.UserLastName = userLastName.String
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, err
	}
	return items, total, nil
}

func sanitizeAdminBotMessageText(text string) string {
	cleaned := strings.TrimSpace(text)
	if cleaned == "" {
		return "[unsupported message]"
	}
	return cleaned
}

func nullInt64(value int64) interface{} {
	if value <= 0 {
		return nil
	}
	return value
}
