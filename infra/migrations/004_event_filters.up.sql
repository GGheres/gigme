ALTER TABLE events
  ADD COLUMN IF NOT EXISTS filters text[] NOT NULL DEFAULT '{}'::text[];
