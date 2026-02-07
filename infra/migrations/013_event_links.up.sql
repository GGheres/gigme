ALTER TABLE events
  ADD COLUMN IF NOT EXISTS links text[] NOT NULL DEFAULT '{}'::text[];
