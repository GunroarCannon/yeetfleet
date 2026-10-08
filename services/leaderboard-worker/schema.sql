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

-- Daily Sortie runs (G3). A ticket (/run/start) opens a run; /run/finish
-- closes it once. Ranked runs need a Genesis Token and are counted per
-- token (genesis_mint), so one Seeker is one ranked pilot.
CREATE TABLE IF NOT EXISTS runs (
  id TEXT PRIMARY KEY,
  pubkey TEXT NOT NULL,
  genesis_mint TEXT,
  day TEXT NOT NULL,                    -- UTC date, YYYY-MM-DD
  ranked INTEGER NOT NULL,
  started_at INTEGER NOT NULL,          -- ms
  finished_at INTEGER,
  points INTEGER,
  won INTEGER,
  time_sec REAL,
  kills INTEGER
);
CREATE INDEX IF NOT EXISTS runs_board ON runs (day, ranked, points);
CREATE INDEX IF NOT EXISTS runs_pilot ON runs (pubkey, day);
CREATE INDEX IF NOT EXISTS runs_genesis ON runs (genesis_mint, day, ranked);

-- Extra ranked attempts bought with SKR (G4), per Genesis Token and day.
CREATE TABLE IF NOT EXISTS extra_attempts (
  genesis_mint TEXT NOT NULL,
  day TEXT NOT NULL,
  count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (genesis_mint, day)
);
