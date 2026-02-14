ALTER TABLE payment_settings
ADD COLUMN IF NOT EXISTS phone_enabled boolean NOT NULL DEFAULT true,
ADD COLUMN IF NOT EXISTS usdt_enabled boolean NOT NULL DEFAULT true,
ADD COLUMN IF NOT EXISTS payment_qr_enabled boolean NOT NULL DEFAULT true,
ADD COLUMN IF NOT EXISTS sbp_enabled boolean NOT NULL DEFAULT true;
