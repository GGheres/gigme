DELETE FROM event_media;

UPDATE users
SET photo_url = NULL
WHERE photo_url IS NOT NULL;

SELECT setval(
	pg_get_serial_sequence('event_media', 'id'),
	COALESCE((SELECT MAX(id) FROM event_media), 0) + 1,
	false
);
