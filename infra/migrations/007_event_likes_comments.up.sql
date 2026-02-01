CREATE TABLE IF NOT EXISTS event_likes (
	event_id bigint NOT NULL REFERENCES events(id) ON DELETE CASCADE,
	user_id bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
	created_at timestamptz NOT NULL DEFAULT now(),
	PRIMARY KEY (event_id, user_id)
);

CREATE INDEX IF NOT EXISTS event_likes_event_ix ON event_likes(event_id);
CREATE INDEX IF NOT EXISTS event_likes_user_ix ON event_likes(user_id);

CREATE TABLE IF NOT EXISTS event_comments (
	id bigserial PRIMARY KEY,
	event_id bigint NOT NULL REFERENCES events(id) ON DELETE CASCADE,
	user_id bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
	body text NOT NULL,
	created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS event_comments_event_ix ON event_comments(event_id);
CREATE INDEX IF NOT EXISTS event_comments_user_ix ON event_comments(user_id);
