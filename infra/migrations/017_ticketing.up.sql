CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS ticket_products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id bigint NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  type text NOT NULL CHECK (type IN ('SINGLE', 'GROUP2', 'GROUP10')),
  price_cents bigint NOT NULL CHECK (price_cents >= 0),
  inventory_limit int NULL CHECK (inventory_limit > 0),
  sold_count int NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  created_by bigint NULL REFERENCES users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (event_id, type)
);

CREATE TABLE IF NOT EXISTS transfer_products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id bigint NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  direction text NOT NULL CHECK (direction IN ('THERE', 'BACK', 'ROUNDTRIP')),
  price_cents bigint NOT NULL CHECK (price_cents >= 0),
  info_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  inventory_limit int NULL CHECK (inventory_limit > 0),
  sold_count int NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  created_by bigint NULL REFERENCES users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (event_id, direction)
);

CREATE TABLE IF NOT EXISTS promo_codes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  discount_type text NOT NULL CHECK (discount_type IN ('PERCENT', 'FIXED')),
  value bigint NOT NULL CHECK (value >= 0),
  usage_limit int NULL CHECK (usage_limit > 0),
  used_count int NOT NULL DEFAULT 0,
  active_from timestamptz NULL,
  active_to timestamptz NULL,
  event_id bigint NULL REFERENCES events(id) ON DELETE SET NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_by bigint NULL REFERENCES users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  event_id bigint NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  status text NOT NULL CHECK (status IN ('PENDING', 'CONFIRMED', 'CANCELED', 'REDEEMED')),
  payment_method text NOT NULL CHECK (payment_method IN ('PHONE', 'USDT', 'PAYMENT_QR')),
  payment_reference text NULL,
  payment_notes text NULL,
  promo_code_id uuid NULL REFERENCES promo_codes(id) ON DELETE SET NULL,
  subtotal_cents bigint NOT NULL CHECK (subtotal_cents >= 0),
  discount_cents bigint NOT NULL DEFAULT 0 CHECK (discount_cents >= 0),
  total_cents bigint NOT NULL CHECK (total_cents >= 0),
  currency text NOT NULL DEFAULT 'USD',
  confirmed_at timestamptz NULL,
  canceled_at timestamptz NULL,
  redeemed_at timestamptz NULL,
  confirmed_by bigint NULL REFERENCES users(id) ON DELETE SET NULL,
  canceled_by bigint NULL REFERENCES users(id) ON DELETE SET NULL,
  canceled_reason text NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS order_items (
  id bigserial PRIMARY KEY,
  order_id uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  item_type text NOT NULL CHECK (item_type IN ('TICKET', 'TRANSFER')),
  product_id uuid NOT NULL,
  product_ref text NOT NULL,
  quantity int NOT NULL CHECK (quantity > 0),
  unit_price_cents bigint NOT NULL CHECK (unit_price_cents >= 0),
  line_total_cents bigint NOT NULL CHECK (line_total_cents >= 0),
  meta_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS tickets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  user_id bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  event_id bigint NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  ticket_type text NOT NULL CHECK (ticket_type IN ('SINGLE', 'GROUP2', 'GROUP10')),
  quantity int NOT NULL CHECK (quantity > 0),
  qr_payload text NULL,
  qr_payload_hash text NULL,
  qr_issued_at timestamptz NULL,
  redeemed_at timestamptz NULL,
  redeemed_by bigint NULL REFERENCES users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ticket_products_event_active_ix ON ticket_products(event_id, is_active);
CREATE INDEX IF NOT EXISTS transfer_products_event_active_ix ON transfer_products(event_id, is_active);
CREATE INDEX IF NOT EXISTS promo_codes_code_ix ON promo_codes(lower(code));
CREATE INDEX IF NOT EXISTS orders_user_created_ix ON orders(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS orders_event_status_created_ix ON orders(event_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS orders_status_created_ix ON orders(status, created_at DESC);
CREATE INDEX IF NOT EXISTS order_items_order_ix ON order_items(order_id);
CREATE INDEX IF NOT EXISTS tickets_order_ix ON tickets(order_id);
CREATE INDEX IF NOT EXISTS tickets_user_event_ix ON tickets(user_id, event_id);
CREATE INDEX IF NOT EXISTS tickets_event_redeemed_ix ON tickets(event_id, redeemed_at);
