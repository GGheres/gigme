DROP INDEX IF EXISTS events_access_key_uix;

ALTER TABLE events
  DROP COLUMN IF EXISTS access_key,
  DROP COLUMN IF EXISTS is_private;
