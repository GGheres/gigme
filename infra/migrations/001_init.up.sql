CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE IF NOT EXISTS users (
	id bigserial PRIMARY KEY,
	telegram_id bigint UNIQUE NOT NULL,
	username text NULL,
	first_name text NOT NULL,
	last_name text NULL,
	photo_url text NULL,
	created_at timestamptz NOT NULL DEFAULT now(),
	updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS events (
	id bigserial PRIMARY KEY,
	creator_user_id bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
	title text NOT NULL,
	description text NOT NULL,
	starts_at timestamptz NOT NULL,
	ends_at timestamptz NULL,
	location geography(Point, 4326) NOT NULL,
	address_label text NULL,
	capacity int NULL,
	is_hidden bool NOT NULL DEFAULT false,
	promoted_until timestamptz NULL,
	created_at timestamptz NOT NULL DEFAULT now(),
	updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS event_media (
	id bigserial PRIMARY KEY,
	event_id bigint NOT NULL REFERENCES events(id) ON DELETE CASCADE,
	url text NOT NULL,
	type text NOT NULL DEFAULT 'image',
	created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS event_participants (
	event_id bigint NOT NULL REFERENCES events(id) ON DELETE CASCADE,
	user_id bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
	status text NOT NULL DEFAULT 'joined',
	joined_at timestamptz NOT NULL DEFAULT now(),
	PRIMARY KEY (event_id, user_id)
);

CREATE TABLE IF NOT EXISTS notification_jobs (
	id bigserial PRIMARY KEY,
	user_id bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
	event_id bigint NULL REFERENCES events(id) ON DELETE CASCADE,
	kind text NOT NULL,
	run_at timestamptz NOT NULL,
	payload jsonb NOT NULL DEFAULT '{}'::jsonb,
	status text NOT NULL DEFAULT 'pending',
	attempts int NOT NULL DEFAULT 0,
	last_error text NULL,
	created_at timestamptz NOT NULL DEFAULT now(),
	updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS users_telegram_id_uix ON users(telegram_id);
CREATE INDEX IF NOT EXISTS events_starts_at_ix ON events(starts_at);
CREATE INDEX IF NOT EXISTS events_location_gix ON events USING GIST (location);
CREATE INDEX IF NOT EXISTS event_participants_user_ix ON event_participants(user_id);
CREATE INDEX IF NOT EXISTS event_participants_event_ix ON event_participants(event_id);
CREATE INDEX IF NOT EXISTS notification_jobs_status_run_ix ON notification_jobs(status, run_at);
