ALTER TABLE landing_content
  ADD COLUMN IF NOT EXISTS sonic_stage_title text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS sonic_stage_description text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS sonic_stage_image_url text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS lensound_stage_title text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS lensound_stage_description text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS lensound_stage_image_url text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS space_stage_title text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS space_stage_description text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS space_stage_image_url text NOT NULL DEFAULT '';
