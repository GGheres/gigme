ALTER TABLE payment_settings
DROP COLUMN IF EXISTS payment_qr_data;

UPDATE orders
SET currency = 'USD'
WHERE upper(currency) = 'RUB';

ALTER TABLE orders
ALTER COLUMN currency SET DEFAULT 'USD';
