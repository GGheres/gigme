CREATE UNIQUE INDEX transfer_products_event_direction_landing_key_uidx
ON transfer_products (
	event_id,
	direction,
	(COALESCE(NULLIF(lower(info_json->>'landingKey'), ''), 'space'))
);
