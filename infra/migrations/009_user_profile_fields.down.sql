ALTER TABLE users
  DROP COLUMN IF EXISTS balance_tokens,
  DROP COLUMN IF EXISTS rating_count,
  DROP COLUMN IF EXISTS rating;
