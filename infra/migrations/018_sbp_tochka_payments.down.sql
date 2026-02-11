DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS sbp_qr;

ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_status_check;

UPDATE orders
SET status = 'CONFIRMED'
WHERE status = 'PAID';

ALTER TABLE orders
  ADD CONSTRAINT orders_status_check
  CHECK (status IN ('PENDING', 'CONFIRMED', 'CANCELED', 'REDEEMED'));

ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_payment_method_check;

UPDATE orders
SET payment_method = 'PAYMENT_QR'
WHERE payment_method = 'TOCHKA_SBP_QR';

ALTER TABLE orders
  ADD CONSTRAINT orders_payment_method_check
  CHECK (payment_method IN ('PHONE', 'USDT', 'PAYMENT_QR'));
