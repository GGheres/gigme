ALTER TABLE events
  DROP COLUMN IF EXISTS contact_telegram,
  DROP COLUMN IF EXISTS contact_whatsapp,
  DROP COLUMN IF EXISTS contact_wechat,
  DROP COLUMN IF EXISTS contact_fb_messenger,
  DROP COLUMN IF EXISTS contact_snapchat;
