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

    case "SELECT MAX(day) as day FROM items": {
      const days = tables.items.map((r) => r.day).filter((d) => typeof d === "string" && d.length > 0);
      const max = days.length ? [...days].sort().slice(-1)[0] : null;
      return [{ day: max }];
    }

    case "SELECT * FROM items WHERE id = ?":
      return tables.items.filter((r) => r.id === args[0]);

    case "SELECT * FROM items WHERE platform = ? AND queue = ? AND status = 'open' ORDER BY created ASC": {
      const matches = tables.items.filter(
        (r) => r.platform === args[0] && r.queue === args[1] && r.status === "open"
      );
      matches.sort((a, b) => a.created - b.created);
      return matches;
    }

    case "SELECT COUNT(*) as c FROM items WHERE platform = ? AND queue = ? AND status = ? AND day = ?": {
      const c = tables.items.filter(
        (r) => r.platform === args[0] && r.queue === args[1] && r.status === args[2] && r.day === args[3]
      ).length;
      return [{ c }];
    }

    case "SELECT * FROM items WHERE status = ? AND day = ? ORDER BY updated DESC LIMIT ?": {
      const matches = tables.items.filter((r) => r.status === args[0] && r.day === args[1]);
      matches.sort((a, b) => b.updated - a.updated);
      return matches.slice(0, args[2]);
    }

    case "SELECT * FROM items WHERE status = ? ORDER BY updated DESC LIMIT ?": {
      const matches = tables.items.filter((r) => r.status === args[0]);
      matches.sort((a, b) => b.updated - a.updated);
      return matches.slice(0, args[1]);
    }

    case "SELECT * FROM items WHERE day = ? ORDER BY updated DESC LIMIT ?": {
      const matches = tables.items.filter((r) => r.day === args[0]);
      matches.sort((a, b) => b.updated - a.updated);
      return matches.slice(0, args[1]);
    }

    case "SELECT * FROM items ORDER BY updated DESC LIMIT ?": {
      const matches = [...tables.items].sort((a, b) => b.updated - a.updated);
      return matches.slice(0, args[0]);
    }

    case "SELECT * FROM events WHERE seq > ? ORDER BY seq ASC LIMIT ?": {
      const matches = tables.events.filter((r) => r.seq > args[0]);
      matches.sort((a, b) => a.seq - b.seq);
      return matches.slice(0, args[1]);
    }

    case "SELECT v FROM kv WHERE k = ?":
      return tables.kv.filter((r) => r.k === args[0]).map((r) => ({ v: r.v }));

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

    case "INSERT INTO items (id, platform, queue, status, title, body, url, target, why, source, photos, day, created, updated, link, skip_reason, skip_note, extra) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)":
      tables.items.push({
        id: args[0],
        platform: args[1],
        queue: args[2],
        status: args[3],
        title: args[4],
        body: args[5],
        url: args[6],
        target: args[7],
        why: args[8],
        source: args[9],
        photos: args[10],
        day: args[11],
        created: args[12],
        updated: args[13],
        link: args[14],
        skip_reason: args[15],
        skip_note: args[16],
        extra: args[17],
      });
      return 1;

    case "UPDATE items SET platform = ?, queue = ?, title = ?, body = ?, url = ?, target = ?, why = ?, source = ?, photos = ?, day = ?, updated = ?, extra = ? WHERE id = ?": {
      const row = tables.items.find((r) => r.id === args[12]);
      if (!row) return 0;
      row.platform = args[0];
      row.queue = args[1];
      row.title = args[2];
      row.body = args[3];
      row.url = args[4];
      row.target = args[5];
      row.why = args[6];
      row.source = args[7];
      row.photos = args[8];
      row.day = args[9];
      row.updated = args[10];
      row.extra = args[11];
      return 1;
    }

    case "UPDATE items SET platform = ?, queue = ?, status = ?, title = ?, body = ?, url = ?, target = ?, why = ?, source = ?, photos = ?, day = ?, updated = ?, link = ?, skip_reason = ?, skip_note = ?, extra = ? WHERE id = ?": {
      const row = tables.items.find((r) => r.id === args[16]);
      if (!row) return 0;
      row.platform = args[0];
      row.queue = args[1];
      row.status = args[2];
      row.title = args[3];
      row.body = args[4];
      row.url = args[5];
      row.target = args[6];
      row.why = args[7];
      row.source = args[8];
      row.photos = args[9];
      row.day = args[10];
      row.updated = args[11];
      row.link = args[12];
      row.skip_reason = args[13];
      row.skip_note = args[14];
      row.extra = args[15];
      return 1;
    }

    case "UPDATE items SET status = 'done', link = ?, updated = ? WHERE id = ?": {
      const row = tables.items.find((r) => r.id === args[2]);
      if (!row) return 0;
      row.status = "done";
      row.link = args[0];
      row.updated = args[1];
      return 1;
    }

    case "UPDATE items SET status = 'skipped', skip_reason = ?, skip_note = ?, updated = ? WHERE id = ?": {
      const row = tables.items.find((r) => r.id === args[3]);
      if (!row) return 0;
      row.status = "skipped";
      row.skip_reason = args[0];
      row.skip_note = args[1];
      row.updated = args[2];
      return 1;
    }

    case "UPDATE items SET link = ?, updated = ? WHERE id = ?": {
      const row = tables.items.find((r) => r.id === args[2]);
      if (!row) return 0;
      row.link = args[0];
      row.updated = args[1];
      return 1;
    }

    case "INSERT INTO events (item, kind, link, reason, note, at) VALUES (?, ?, ?, ?, ?, ?)": {
      tables._eventSeq = (tables._eventSeq || 0) + 1;
      tables.events.push({
        seq: tables._eventSeq,
        item: args[0],
        kind: args[1],
        link: args[2],
        reason: args[3],
        note: args[4],
        at: args[5],
      });
      return 1;
    }

    case "INSERT INTO kv (k, v, updated) VALUES (?, ?, ?) ON CONFLICT(k) DO UPDATE SET v = excluded.v, updated = excluded.updated": {
      const row = tables.kv.find((r) => r.k === args[0]);
      if (row) {
        row.v = args[1];
        row.updated = args[2];
      } else {
        tables.kv.push({ k: args[0], v: args[1], updated: args[2] });
      }
      return 1;
    }

    default:
      throw new Error(`FakeD1: unhandled mutation: ${sql}`);
  }
}

class FakeD1 {
  constructor() {
    this.tables = { shares: [], rules: [], items: [], events: [], kv: [] };
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
    ENGINE_TOKEN: "test-engine-token",
    ...overrides,
  };
}

export { FakeD1, FakeR2, makeEnv };
