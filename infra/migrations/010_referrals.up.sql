CREATE TABLE IF NOT EXISTS referral_codes (
  id bigserial PRIMARY KEY,
  code text UNIQUE NOT NULL,
  owner_user_id bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS referral_codes_owner_uix ON referral_codes(owner_user_id);

CREATE TABLE IF NOT EXISTS referral_claims (
  id bigserial PRIMARY KEY,
  referral_code_id bigint NOT NULL REFERENCES referral_codes(id) ON DELETE CASCADE,
  event_id bigint NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  invitee_user_id bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  inviter_user_id bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  bonus_amount int NOT NULL DEFAULT 100,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS referral_claims_invitee_uix ON referral_claims(invitee_user_id);
CREATE UNIQUE INDEX IF NOT EXISTS referral_claims_code_invitee_uix ON referral_claims(referral_code_id, invitee_user_id);
CREATE INDEX IF NOT EXISTS referral_claims_inviter_ix ON referral_claims(inviter_user_id);
