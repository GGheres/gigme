DROP INDEX IF EXISTS admin_broadcast_jobs_status_created_ix;
DROP INDEX IF EXISTS admin_broadcast_jobs_broadcast_status_ix;
DROP INDEX IF EXISTS users_is_blocked_ix;

DROP TABLE IF EXISTS admin_broadcast_jobs;
DROP TABLE IF EXISTS admin_broadcasts;

ALTER TABLE users
  DROP COLUMN IF EXISTS blocked_at,
  DROP COLUMN IF EXISTS blocked_reason,
  DROP COLUMN IF EXISTS is_blocked;
