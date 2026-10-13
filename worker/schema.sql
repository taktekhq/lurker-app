-- D1 schema for lurker-app. Apply with deploy.sh, or by hand via the
-- Cloudflare REST API's /d1/database/:id/query endpoint.

CREATE TABLE IF NOT EXISTS shares (
  id TEXT PRIMARY KEY,
  note TEXT,
  photos TEXT NOT NULL,      -- JSON array of R2 keys
  status TEXT NOT NULL,      -- new | drafting | drafted | failed | posted | skipped
  drafts TEXT,               -- JSON array of Draft, or NULL
  error TEXT,
  created INTEGER NOT NULL,  -- epoch ms
  updated INTEGER NOT NULL   -- epoch ms
);

CREATE INDEX IF NOT EXISTS shares_status_idx ON shares(status);
CREATE INDEX IF NOT EXISTS shares_created_idx ON shares(created);

CREATE TABLE IF NOT EXISTS rules (
  sub TEXT PRIMARY KEY,
  rules TEXT NOT NULL,       -- JSON array of strings
  updated INTEGER NOT NULL   -- epoch ms
);

-- SPEC-v2.md: post and comment queues, per platform (reddit, hn).

CREATE TABLE IF NOT EXISTS items (
  id TEXT PRIMARY KEY,
  platform TEXT NOT NULL,     -- reddit | hn
  queue TEXT NOT NULL,        -- post | comment
  status TEXT NOT NULL,       -- open | done | skipped | expired
  title TEXT,
  body TEXT,
  url TEXT,                   -- the thread to answer, or the submit page
  target TEXT,                -- reddit: subreddit; hn: null
  why TEXT,
  source TEXT,                -- kbase | work | link | thread | photo
  photos TEXT,                -- JSON array of R2 keys, photo items only
  day TEXT,                   -- the engine's local calendar day, "YYYY-MM-DD"
  created INTEGER NOT NULL,
  updated INTEGER NOT NULL,
  link TEXT,
  skip_reason TEXT,           -- bad | later
  skip_note TEXT,
  extra TEXT                  -- JSON, engine-owned
);

CREATE INDEX IF NOT EXISTS items_platform_queue_status_idx ON items(platform, queue, status);
CREATE INDEX IF NOT EXISTS items_day_idx ON items(day);
CREATE INDEX IF NOT EXISTS items_updated_idx ON items(updated);

CREATE TABLE IF NOT EXISTS events (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  item TEXT NOT NULL,
  kind TEXT NOT NULL,         -- done | skip | link
  link TEXT,
  reason TEXT,
  note TEXT,
  at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS kv (
  k TEXT PRIMARY KEY,
  v TEXT NOT NULL,
  updated INTEGER NOT NULL    -- growth JSON lives at k = "growth"
);
