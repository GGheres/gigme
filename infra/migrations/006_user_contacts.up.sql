CREATE TABLE IF NOT EXISTS user_contact_matches (
  user_id bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  contact_user_id bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, contact_user_id)
);

CREATE INDEX IF NOT EXISTS user_contact_matches_contact_user_ix ON user_contact_matches(contact_user_id);
