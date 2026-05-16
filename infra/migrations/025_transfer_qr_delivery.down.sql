DELETE FROM tickets
WHERE ticket_type IN (
  'TRANSFER_THERE',
  'TRANSFER_BACK',
  'TRANSFER_ROUNDTRIP'
);

ALTER TABLE tickets DROP CONSTRAINT IF EXISTS tickets_ticket_type_check;

ALTER TABLE tickets
  ADD CONSTRAINT tickets_ticket_type_check
  CHECK (ticket_type IN ('SINGLE', 'GROUP2', 'GROUP10'));

DROP INDEX IF EXISTS tickets_qr_delivery_pending_ix;

ALTER TABLE tickets
  DROP COLUMN IF EXISTS qr_delivery_error,
  DROP COLUMN IF EXISTS qr_delivered_at;
