ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_status_check;

UPDATE orders
SET status = 'PAID'
WHERE status = 'CONFIRMED';

ALTER TABLE orders
  ADD CONSTRAINT orders_status_check
  CHECK (status IN ('PENDING', 'PAID', 'CANCELED', 'REDEEMED'));

ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_payment_method_check;

ALTER TABLE orders
  ADD CONSTRAINT orders_payment_method_check
  CHECK (payment_method IN ('PHONE', 'USDT', 'PAYMENT_QR', 'TOCHKA_SBP_QR'));

CREATE TABLE IF NOT EXISTS sbp_qr (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  qrc_id text NOT NULL,
  payload text NOT NULL,
  merchant_id text NOT NULL,
  account_id text NOT NULL,
  status text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (order_id),
  UNIQUE (qrc_id)
);

CREATE INDEX IF NOT EXISTS sbp_qr_status_created_ix ON sbp_qr(status, created_at DESC);

CREATE TABLE IF NOT EXISTS payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  provider text NOT NULL,
  provider_payment_id text NULL,
  amount bigint NOT NULL CHECK (amount >= 0),
  status text NOT NULL,
  raw_response_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (order_id, provider)
);

CREATE INDEX IF NOT EXISTS payments_provider_status_created_ix ON payments(provider, status, created_at DESC);
CREATE INDEX IF NOT EXISTS payments_provider_payment_id_ix ON payments(provider_payment_id);
