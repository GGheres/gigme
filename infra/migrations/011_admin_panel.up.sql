ALTER TABLE users
  ADD COLUMN IF NOT EXISTS is_blocked boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS blocked_reason text NULL,
  ADD COLUMN IF NOT EXISTS blocked_at timestamptz NULL,
  ADD COLUMN IF NOT EXISTS last_seen_at timestamptz NULL;

CREATE TABLE IF NOT EXISTS admin_broadcasts (
  id bigserial PRIMARY KEY,
  admin_user_id bigint NOT NULL REFERENCES users(id),
  audience text NOT NULL,
  payload jsonb NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS admin_broadcast_jobs (
  id bigserial PRIMARY KEY,
  broadcast_id bigint NOT NULL REFERENCES admin_broadcasts(id) ON DELETE CASCADE,
  target_user_id bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending',
  attempts int NOT NULL DEFAULT 0,
  last_error text NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS users_is_blocked_ix ON users(is_blocked);
CREATE INDEX IF NOT EXISTS admin_broadcast_jobs_broadcast_status_ix ON admin_broadcast_jobs(broadcast_id, status);
CREATE INDEX IF NOT EXISTS admin_broadcast_jobs_status_created_ix ON admin_broadcast_jobs(status, created_at);
