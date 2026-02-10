DROP INDEX IF EXISTS events_landing_published_ix;

ALTER TABLE events
  DROP COLUMN IF EXISTS is_landing_published;
