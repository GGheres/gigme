CREATE TABLE IF NOT EXISTS payment_settings_scoped (
  scope text PRIMARY KEY CHECK (scope IN ('TICKET', 'TRANSFER')),
  phone_number text NOT NULL DEFAULT '',
  usdt_wallet text NOT NULL DEFAULT '',
  usdt_network text NOT NULL DEFAULT 'TRC20',
  usdt_memo text NOT NULL DEFAULT '',
  payment_qr_data text NOT NULL DEFAULT '',
  phone_enabled boolean NOT NULL DEFAULT true,
  usdt_enabled boolean NOT NULL DEFAULT true,
  payment_qr_enabled boolean NOT NULL DEFAULT true,
  sbp_enabled boolean NOT NULL DEFAULT true,
  phone_description text NOT NULL DEFAULT '',
  usdt_description text NOT NULL DEFAULT '',
  qr_description text NOT NULL DEFAULT '',
  sbp_description text NOT NULL DEFAULT '',
  updated_by bigint NULL REFERENCES users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO payment_settings_scoped (
  scope,
  phone_number,
  usdt_wallet,
  usdt_network,
  usdt_memo,
  payment_qr_data,
  phone_enabled,
  usdt_enabled,
  payment_qr_enabled,
  sbp_enabled,
  phone_description,
  usdt_description,
  qr_description,
  sbp_description,
  updated_by,
  created_at,
  updated_at
)
SELECT
  scope,
  phone_number,
  usdt_wallet,
  usdt_network,
  usdt_memo,
  payment_qr_data,
  phone_enabled,
  usdt_enabled,
  payment_qr_enabled,
  sbp_enabled,
  phone_description,
  usdt_description,
  qr_description,
  sbp_description,
  updated_by,
  created_at,
  updated_at
FROM payment_settings
CROSS JOIN (VALUES ('TICKET'), ('TRANSFER')) AS scopes(scope)
WHERE id = 1
ON CONFLICT (scope) DO NOTHING;

