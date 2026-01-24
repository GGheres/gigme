DROP INDEX IF EXISTS users_last_seen_at_ix;
DROP INDEX IF EXISTS users_last_location_gix;

ALTER TABLE users
	DROP COLUMN IF EXISTS last_seen_at,
	DROP COLUMN IF EXISTS last_location;
