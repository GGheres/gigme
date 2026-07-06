UPDATE transfer_products
SET info_json = jsonb_set(
	COALESCE(info_json, '{}'::jsonb),
	'{landingKey}',
	to_jsonb(
		CASE
			WHEN lower(COALESCE(info_json->>'landingKey', '')) = 'iskry' THEN 'iskry'
			ELSE 'space'
		END
	),
	true
);

ALTER TABLE transfer_products
DROP CONSTRAINT IF EXISTS transfer_products_event_id_direction_key;

DROP INDEX IF EXISTS transfer_products_event_direction_landing_key_uidx;

CREATE UNIQUE INDEX transfer_products_event_direction_landing_key_uidx
ON transfer_products (
	event_id,
	direction,
	(COALESCE(NULLIF(lower(info_json->>'landingKey'), ''), 'space'))
);
