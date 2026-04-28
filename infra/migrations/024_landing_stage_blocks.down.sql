ALTER TABLE landing_content
  DROP COLUMN IF EXISTS space_stage_image_url,
  DROP COLUMN IF EXISTS space_stage_description,
  DROP COLUMN IF EXISTS space_stage_title,
  DROP COLUMN IF EXISTS lensound_stage_image_url,
  DROP COLUMN IF EXISTS lensound_stage_description,
  DROP COLUMN IF EXISTS lensound_stage_title,
  DROP COLUMN IF EXISTS sonic_stage_image_url,
  DROP COLUMN IF EXISTS sonic_stage_description,
  DROP COLUMN IF EXISTS sonic_stage_title;
