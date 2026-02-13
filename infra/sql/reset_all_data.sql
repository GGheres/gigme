DO $$
DECLARE
	table_list text;
BEGIN
	SELECT string_agg(format('%I.%I', schemaname, tablename), ', ')
	INTO table_list
	FROM pg_tables
	WHERE schemaname = 'public'
		AND tablename <> 'schema_migrations';

	IF COALESCE(table_list, '') <> '' THEN
		EXECUTE 'TRUNCATE TABLE ' || table_list || ' RESTART IDENTITY CASCADE';
	END IF;
END $$;

INSERT INTO payment_settings (id)
VALUES (1)
ON CONFLICT (id) DO NOTHING;
