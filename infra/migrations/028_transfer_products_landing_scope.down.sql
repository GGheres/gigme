DROP INDEX IF EXISTS transfer_products_event_direction_landing_key_uidx;

ALTER TABLE transfer_products
ADD CONSTRAINT transfer_products_event_id_direction_key
UNIQUE (event_id, direction);
