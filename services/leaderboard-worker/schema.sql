-- Yeetfleet leaderboard (Cloudflare D1). Apply with:
--   npx wrangler d1 execute yeetfleet --remote --file schema.sql
-- Every statement is idempotent, so re-running it is safe.

-- One-time sign-in nonces (/auth/challenge → /auth/verify).
CREATE TABLE IF NOT EXISTS nonces (
  nonce TEXT PRIMARY KEY,
  issued_at INTEGER NOT NULL,           -- ms
  used INTEGER NOT NULL DEFAULT 0
);

-- Pilots who have signed in. genesis_mint is the Seeker Genesis Token they
-- held at their last sign-in (null: no Seeker, unranked only).
CREATE TABLE IF NOT EXISTS pilots (
  pubkey TEXT PRIMARY KEY,
  name TEXT NOT NULL DEFAULT '',
  genesis_mint TEXT,
  created_at INTEGER NOT NULL,
  last_seen INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS pilots_genesis ON pilots (genesis_mint);
