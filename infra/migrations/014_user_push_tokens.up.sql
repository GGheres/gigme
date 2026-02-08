CREATE TABLE IF NOT EXISTS user_push_tokens (
  id bigserial PRIMARY KEY,
  user_id bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  platform text NOT NULL,
  token text NOT NULL UNIQUE,
  device_id text NULL,
  app_version text NULL,
  locale text NULL,
  is_active boolean NOT NULL DEFAULT true,
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS user_push_tokens_user_active_ix
  ON user_push_tokens(user_id, is_active, updated_at DESC);

CREATE INDEX IF NOT EXISTS user_push_tokens_platform_active_ix
  ON user_push_tokens(platform, is_active);
