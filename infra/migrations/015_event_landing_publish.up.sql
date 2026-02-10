ALTER TABLE events
  ADD COLUMN IF NOT EXISTS is_landing_published boolean NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS events_landing_published_ix
  ON events (is_landing_published, starts_at)
  WHERE is_hidden = false AND is_private = false;
