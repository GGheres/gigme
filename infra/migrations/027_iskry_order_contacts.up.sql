ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS contact_telegram text NULL,
  ADD COLUMN IF NOT EXISTS contact_name text NULL,
  ADD COLUMN IF NOT EXISTS contact_phone text NULL;
