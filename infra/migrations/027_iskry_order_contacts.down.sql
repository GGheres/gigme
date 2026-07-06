ALTER TABLE orders
  DROP COLUMN IF EXISTS contact_phone,
  DROP COLUMN IF EXISTS contact_name,
  DROP COLUMN IF EXISTS contact_telegram;
