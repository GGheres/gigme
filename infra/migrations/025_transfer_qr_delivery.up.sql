ALTER TABLE tickets
  ADD COLUMN IF NOT EXISTS qr_delivered_at timestamptz NULL,
  ADD COLUMN IF NOT EXISTS qr_delivery_error text NULL;

ALTER TABLE tickets DROP CONSTRAINT IF EXISTS tickets_ticket_type_check;

ALTER TABLE tickets
  ADD CONSTRAINT tickets_ticket_type_check
  CHECK (ticket_type IN (
    'SINGLE',
    'GROUP2',
    'GROUP10',
    'TRANSFER_THERE',
    'TRANSFER_BACK',
    'TRANSFER_ROUNDTRIP'
  ));

CREATE INDEX IF NOT EXISTS tickets_qr_delivery_pending_ix
  ON tickets(order_id, qr_delivered_at)
  WHERE qr_payload IS NOT NULL AND qr_delivered_at IS NULL;
