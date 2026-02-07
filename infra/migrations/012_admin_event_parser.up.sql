CREATE TABLE IF NOT EXISTS admin_event_parser_sources (
  id bigserial PRIMARY KEY,
  source_type text NOT NULL DEFAULT 'auto',
  input text NOT NULL,
  title text NULL,
  is_active boolean NOT NULL DEFAULT true,
  last_parsed_at timestamptz NULL,
  created_by bigint NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS admin_event_parser_events (
  id bigserial PRIMARY KEY,
  source_id bigint NULL REFERENCES admin_event_parser_sources(id) ON DELETE SET NULL,
  source_type text NOT NULL,
  input text NOT NULL,
  name text NOT NULL DEFAULT '',
  date_time timestamptz NULL,
  location text NOT NULL DEFAULT '',
  description text NOT NULL DEFAULT '',
  links text[] NOT NULL DEFAULT '{}'::text[],
  status text NOT NULL DEFAULT 'pending',
  parser_error text NULL,
  parsed_at timestamptz NOT NULL DEFAULT now(),
  imported_event_id bigint NULL REFERENCES events(id) ON DELETE SET NULL,
  imported_by bigint NULL REFERENCES users(id) ON DELETE SET NULL,
  imported_at timestamptz NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT admin_event_parser_events_status_check CHECK (status IN ('pending', 'imported', 'rejected', 'error'))
);

CREATE INDEX IF NOT EXISTS admin_event_parser_sources_active_ix
  ON admin_event_parser_sources(is_active, created_at DESC);

CREATE INDEX IF NOT EXISTS admin_event_parser_events_status_parsed_ix
  ON admin_event_parser_events(status, parsed_at DESC);

CREATE INDEX IF NOT EXISTS admin_event_parser_events_source_ix
  ON admin_event_parser_events(source_id, parsed_at DESC);
