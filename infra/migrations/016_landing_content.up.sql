CREATE TABLE IF NOT EXISTS landing_content (
  id smallint PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  hero_eyebrow text NOT NULL DEFAULT '',
  hero_title text NOT NULL DEFAULT '',
  hero_description text NOT NULL DEFAULT '',
  hero_primary_cta_label text NOT NULL DEFAULT '',
  about_title text NOT NULL DEFAULT '',
  about_description text NOT NULL DEFAULT '',
  partners_title text NOT NULL DEFAULT '',
  partners_description text NOT NULL DEFAULT '',
  footer_text text NOT NULL DEFAULT '',
  updated_by bigint NULL REFERENCES users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO landing_content (id)
VALUES (1)
ON CONFLICT (id) DO NOTHING;
