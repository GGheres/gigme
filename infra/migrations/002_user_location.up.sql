ALTER TABLE users
	ADD COLUMN IF NOT EXISTS last_location geography(Point, 4326) NULL,
	ADD COLUMN IF NOT EXISTS last_seen_at timestamptz NULL;

CREATE INDEX IF NOT EXISTS users_last_location_gix ON users USING GIST (last_location);
CREATE INDEX IF NOT EXISTS users_last_seen_at_ix ON users(last_seen_at);
