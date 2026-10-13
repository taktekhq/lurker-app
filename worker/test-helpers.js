// In-memory fakes for the D1 and R2 bindings, used only by worker.test.js.
// Each fake understands exactly the SQL statements worker.js issues; it is
// not a general SQL engine. Keep this file in sync with worker.js if the
// queries there change.

function normalize(sql) {
  return sql.replace(/\s+/g, " ").trim();
}

function execSelect(sql, args, tables) {
  switch (sql) {
    case "SELECT * FROM shares WHERE id = ?":
      return tables.shares.filter((r) => r.id === args[0]);

    case "SELECT * FROM shares ORDER BY created DESC LIMIT ?": {
      const sorted = [...tables.shares].sort((a, b) => b.created - a.created);
      return sorted.slice(0, args[0]);
    }

    case "SELECT * FROM shares WHERE status = 'new' OR (status = 'drafting' AND updated < ?) ORDER BY created ASC LIMIT 1": {
      const staleBefore = args[0];
      const matches = tables.shares.filter(
        (r) => r.status === "new" || (r.status === "drafting" && r.updated < staleBefore)
      );
      matches.sort((a, b) => a.created - b.created);
      return matches.slice(0, 1);
    }

    case "SELECT sub, rules FROM rules":
      return tables.rules.map((r) => ({ sub: r.sub, rules: r.rules }));

    default:
      throw new Error(`FakeD1: unhandled SELECT: ${sql}`);
  }
}

function execMutate(sql, args, tables) {
  switch (sql) {
    case "INSERT INTO shares (id, note, photos, status, drafts, error, created, updated) VALUES (?, ?, ?, ?, ?, ?, ?, ?)":
      tables.shares.push({
        id: args[0],
        note: args[1],
        photos: args[2],
        status: args[3],
        drafts: args[4],
        error: args[5],
        created: args[6],
        updated: args[7],
      });
      return 1;

    case "DELETE FROM shares WHERE status IN ('posted', 'skipped') AND updated < ?": {
      const before = args[0];
      const keep = tables.shares.filter(
        (r) => !((r.status === "posted" || r.status === "skipped") && r.updated < before)
      );
      const changes = tables.shares.length - keep.length;
      tables.shares = keep;
      return changes;
    }

    case "UPDATE shares SET status = ?, drafts = NULL, error = NULL, updated = ? WHERE id = ?": {
      const row = tables.shares.find((r) => r.id === args[2]);
      if (!row) return 0;
      row.status = args[0];
      row.drafts = null;
      row.error = null;
      row.updated = args[1];
      return 1;
    }

    case "UPDATE shares SET status = ?, updated = ? WHERE id = ?": {
      const row = tables.shares.find((r) => r.id === args[2]);
      if (!row) return 0;
      row.status = args[0];
      row.updated = args[1];
      return 1;
    }

    case "DELETE FROM shares WHERE id = ?": {
      const before = tables.shares.length;
      tables.shares = tables.shares.filter((r) => r.id !== args[0]);
      return before - tables.shares.length;
    }

    case "UPDATE shares SET status = 'drafting', updated = ? WHERE id = ?": {
      const row = tables.shares.find((r) => r.id === args[1]);
      if (!row) return 0;
      row.status = "drafting";
      row.updated = args[0];
      return 1;
    }

    case "UPDATE shares SET status = 'drafted', drafts = ?, error = NULL, updated = ? WHERE id = ?": {
      const row = tables.shares.find((r) => r.id === args[2]);
      if (!row) return 0;
      row.status = "drafted";
      row.drafts = args[0];
      row.error = null;
      row.updated = args[1];
      return 1;
    }

    case "UPDATE shares SET status = 'failed', drafts = NULL, error = ?, updated = ? WHERE id = ?": {
      const row = tables.shares.find((r) => r.id === args[2]);
      if (!row) return 0;
      row.status = "failed";
      row.drafts = null;
      row.error = args[0];
      row.updated = args[1];
      return 1;
    }

    case "UPDATE rules SET rules = ?, updated = ? WHERE sub = ?": {
      const row = tables.rules.find((r) => r.sub === args[2]);
      if (!row) return 0;
      row.rules = args[0];
      row.updated = args[1];
      return 1;
    }

    case "INSERT INTO rules (sub, rules, updated) VALUES (?, ?, ?)":
      tables.rules.push({ sub: args[0], rules: args[1], updated: args[2] });
      return 1;

    default:
      throw new Error(`FakeD1: unhandled mutation: ${sql}`);
  }
}

class FakeD1 {
  constructor() {
    this.tables = { shares: [], rules: [] };
  }

  prepare(sql) {
    const normalized = normalize(sql);
    const tables = this.tables;
    return {
      _args: [],
      bind(...args) {
        this._args = args;
        return this;
      },
      async first() {
        const rows = execSelect(normalized, this._args, tables);
        return rows[0] || null;
      },
      async all() {
        const rows = execSelect(normalized, this._args, tables);
        return { results: rows };
      },
      async run() {
        const changes = execMutate(normalized, this._args, tables);
        return { success: true, meta: { changes } };
      },
    };
  }
}

class FakeR2 {
  constructor() {
    this.objects = new Map();
  }

  async put(key, value, opts) {
    this.objects.set(key, {
      body: value,
      httpMetadata: (opts && opts.httpMetadata) || {},
    });
    return { key };
  }

  async get(key) {
    const obj = this.objects.get(key);
    if (!obj) return null;
    return { body: obj.body, httpMetadata: obj.httpMetadata };
  }

  async delete(key) {
    this.objects.delete(key);
  }
}

function makeEnv(overrides = {}) {
  return {
    DB: new FakeD1(),
    PHOTOS: new FakeR2(),
    APP_TOKEN: "test-app-token",
    DRAFTER_TOKEN: "test-drafter-token",
    ...overrides,
  };
}

export { FakeD1, FakeR2, makeEnv };
