ALTER TABLE events
  ADD COLUMN IF NOT EXISTS contact_telegram text NULL,
  ADD COLUMN IF NOT EXISTS contact_whatsapp text NULL,
  ADD COLUMN IF NOT EXISTS contact_wechat text NULL,
  ADD COLUMN IF NOT EXISTS contact_fb_messenger text NULL,
  ADD COLUMN IF NOT EXISTS contact_snapchat text NULL;
