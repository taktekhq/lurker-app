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
