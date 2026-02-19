CREATE TABLE IF NOT EXISTS admin_bot_messages (
  id bigserial PRIMARY KEY,
  chat_id bigint NOT NULL,
  direction text NOT NULL,
  message_text text NOT NULL,
  telegram_message_id bigint NULL,
  sender_telegram_id bigint NULL,
  sender_username text NULL,
  sender_first_name text NULL,
  sender_last_name text NULL,
  admin_telegram_id bigint NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT admin_bot_messages_direction_check
    CHECK (direction IN ('INCOMING', 'OUTGOING'))
);

CREATE INDEX IF NOT EXISTS admin_bot_messages_chat_created_ix
  ON admin_bot_messages(chat_id, created_at DESC);

CREATE INDEX IF NOT EXISTS admin_bot_messages_created_ix
  ON admin_bot_messages(created_at DESC);
