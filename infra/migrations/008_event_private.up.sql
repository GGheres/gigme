ALTER TABLE events
  ADD COLUMN IF NOT EXISTS is_private bool NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS access_key text NULL;

CREATE UNIQUE INDEX IF NOT EXISTS events_access_key_uix
  ON events(access_key)
  WHERE access_key IS NOT NULL;
