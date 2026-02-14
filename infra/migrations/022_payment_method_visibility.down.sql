ALTER TABLE payment_settings
DROP COLUMN IF EXISTS phone_enabled,
DROP COLUMN IF EXISTS usdt_enabled,
DROP COLUMN IF EXISTS payment_qr_enabled,
DROP COLUMN IF EXISTS sbp_enabled;
