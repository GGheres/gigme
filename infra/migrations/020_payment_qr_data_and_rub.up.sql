ALTER TABLE payment_settings
ADD COLUMN IF NOT EXISTS payment_qr_data text NOT NULL DEFAULT '';

ALTER TABLE orders
ALTER COLUMN currency SET DEFAULT 'RUB';

UPDATE orders
SET currency = 'RUB'
WHERE currency IS NULL
	OR btrim(currency) = ''
	OR upper(currency) = 'USD';
