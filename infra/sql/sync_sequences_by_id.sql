DO $$
DECLARE
	rec record;
	next_value bigint;
BEGIN
	FOR rec IN
		SELECT
			n.nspname AS schema_name,
			c.relname AS table_name,
			a.attname AS column_name,
			pg_get_serial_sequence(format('%I.%I', n.nspname, c.relname), a.attname) AS seq_name
		FROM pg_class c
		JOIN pg_namespace n ON n.oid = c.relnamespace
		JOIN pg_attribute a ON a.attrelid = c.oid
		WHERE c.relkind = 'r'
			AND n.nspname = 'public'
			AND a.attnum > 0
			AND NOT a.attisdropped
	LOOP
		IF rec.seq_name IS NULL THEN
			CONTINUE;
		END IF;

		EXECUTE format(
			'SELECT COALESCE(MAX(%I), 0) + 1 FROM %I.%I',
			rec.column_name,
			rec.schema_name,
			rec.table_name
		)
		INTO next_value;

		PERFORM setval(rec.seq_name, next_value, false);
	END LOOP;
END $$;
