CREATE TABLE IF NOT EXISTS payment_settings (
  id smallint PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  phone_number text NOT NULL DEFAULT '',
  usdt_wallet text NOT NULL DEFAULT '',
  usdt_network text NOT NULL DEFAULT 'TRC20',
  usdt_memo text NOT NULL DEFAULT '',
  phone_description text NOT NULL DEFAULT '',
  usdt_description text NOT NULL DEFAULT '',
  qr_description text NOT NULL DEFAULT '',
  sbp_description text NOT NULL DEFAULT '',
  updated_by bigint NULL REFERENCES users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO payment_settings (id)
VALUES (1)
ON CONFLICT (id) DO NOTHING;
