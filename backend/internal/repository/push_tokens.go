package repository

import (
	"context"

	"gigme/backend/internal/models"
)

// UpsertUserPushToken handles upsert user push token.
func (r *Repository) UpsertUserPushToken(ctx context.Context, token models.UserPushToken) error {
	_, err := r.pool.Exec(ctx, `
INSERT INTO user_push_tokens (
	user_id, platform, token, device_id, app_version, locale,
	is_active, last_seen_at, created_at, updated_at
)
VALUES ($1, $2, $3, $4, $5, $6, true, now(), now(), now())
ON CONFLICT (token) DO UPDATE SET
	user_id = EXCLUDED.user_id,
	platform = EXCLUDED.platform,
	device_id = EXCLUDED.device_id,
	app_version = EXCLUDED.app_version,
	locale = EXCLUDED.locale,
	is_active = true,
	last_seen_at = now(),
	updated_at = now();
`, token.UserID, token.Platform, token.Token, nullString(token.DeviceID), nullString(token.AppVersion), nullString(token.Locale))
	if err != nil {
		return err
	}

	if token.DeviceID != "" {
		_, err = r.pool.Exec(ctx, `
UPDATE user_push_tokens
SET is_active = false,
	updated_at = now()
WHERE user_id = $1
	AND platform = $2
	AND device_id = $3
	AND token <> $4
	AND is_active = true;
`, token.UserID, token.Platform, token.DeviceID, token.Token)
		if err != nil {
			return err
		}
	}

	return nil
}
