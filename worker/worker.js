// Cloudflare Worker for lurker-app. Plain JS module, no build step.
//
// Bindings expected (see wrangler-style metadata in deploy.sh):
//   R2 bucket   PHOTOS
//   D1 database DB
//   secret text APP_TOKEN
//   secret text DRAFTER_TOKEN
//   secret text ENGINE_TOKEN
//
// Routes are documented in SPEC.md (photo shares) and SPEC-v2.md (queues,
// events, growth) at the repo root.

const MAX_PHOTOS = 10;
const MAX_PHOTO_BYTES = 5 * 1024 * 1024;
const MAX_NOTE_CHARS = 2000;
const MAX_SHARES_RETURNED = 100;
const CLAIM_STALE_MS = 15 * 60 * 1000;
const POSTED_RETENTION_MS = 30 * 24 * 60 * 60 * 1000;
const STATUSES = new Set(["new", "drafting", "drafted", "failed", "posted", "skipped"]);

const PLATFORMS = ["reddit", "hn"];
const QUEUES = ["post", "comment"];
// Daily target per queue kind, shown as done_today / target in the app.
// Override with a QUEUE_TARGETS var holding JSON, e.g. {"post":3,"comment":7}.
const DEFAULT_QUEUE_TARGETS = { post: 3, comment: 7 };

function queueTargets(env) {
  try {
    const t = env.QUEUE_TARGETS ? JSON.parse(env.QUEUE_TARGETS) : {};
    return { ...DEFAULT_QUEUE_TARGETS, ...t };
  } catch {
    return DEFAULT_QUEUE_TARGETS;
  }
}
const MAX_EVENTS_RETURNED = 500;
const MAX_ITEMS_RETURNED = 200;
const DEFAULT_ITEMS_LIMIT = 50;

function jsonResponse(body, status = 200, headers = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...headers },
  });
}

function errorResponse(message, status) {
  return jsonResponse({ error: message }, status);
}

function newId() {
  return crypto.randomUUID();
}

function rowToShare(row) {
  if (!row) return null;
  return {
    id: row.id,
    note: row.note ?? null,
    status: row.status,
    created: row.created,
    updated: row.updated,
    photos: row.photos ? JSON.parse(row.photos) : [],
    drafts: row.drafts ? JSON.parse(row.drafts) : [],
    error: row.error ?? null,
  };
}

function rowToItem(row) {
  if (!row) return null;
  return {
    id: row.id,
    platform: row.platform,
    queue: row.queue,
    status: row.status,
    title: row.title ?? null,
    body: row.body ?? null,
    url: row.url ?? null,
    target: row.target ?? null,
    why: row.why ?? null,
    source: row.source ?? null,
    photos: row.photos ? JSON.parse(row.photos) : [],
    day: row.day ?? null,
    created: row.created,
    updated: row.updated,
    link: row.link ?? null,
    skip_reason: row.skip_reason ?? null,
    skip_note: row.skip_note ?? null,
    extra: row.extra ? JSON.parse(row.extra) : null,
  };
}

function rowToEvent(row) {
  return {
    seq: row.seq,
    item: row.item,
    kind: row.kind,
    link: row.link ?? null,
    reason: row.reason ?? null,
    note: row.note ?? null,
    at: row.at,
  };
}

// ---- auth ----

function bearerToken(request) {
  const header = request.headers.get("Authorization") || "";
  const match = /^Bearer (.+)$/.exec(header);
  return match ? match[1] : null;
}

// kinds is an array containing any of "app", "drafter", "engine"
function checkAuth(request, env, kinds) {
  const token = bearerToken(request);
  if (!token) return false;
  if (kinds.includes("app") && env.APP_TOKEN && token === env.APP_TOKEN) return true;
  if (kinds.includes("drafter") && env.DRAFTER_TOKEN && token === env.DRAFTER_TOKEN) return true;
  if (kinds.includes("engine") && env.ENGINE_TOKEN && token === env.ENGINE_TOKEN) return true;
  return false;
}

// ---- db helpers (all go through env.DB, a D1Database-shaped binding) ----

async function dbInsertShare(env, share) {
  await env.DB.prepare(
    "INSERT INTO shares (id, note, photos, status, drafts, error, created, updated) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
  )
    .bind(
      share.id,
      share.note,
      JSON.stringify(share.photos),
      share.status,
      share.drafts ? JSON.stringify(share.drafts) : null,
      share.error,
      share.created,
      share.updated
    )
    .run();
}

async function dbGetShare(env, id) {
  const row = await env.DB.prepare("SELECT * FROM shares WHERE id = ?").bind(id).first();
  return row || null;
}

async function dbCleanupOld(env, now) {
  await env.DB.prepare(
    "DELETE FROM shares WHERE status IN ('posted', 'skipped') AND updated < ?"
  )
    .bind(now - POSTED_RETENTION_MS)
    .run();
}

async function dbListShares(env, limit) {
  const result = await env.DB.prepare(
    "SELECT * FROM shares ORDER BY created DESC LIMIT ?"
  )
    .bind(limit)
    .all();
  return result.results || [];
}

async function dbUpdateStatus(env, id, status, now) {
  if (status === "new") {
    await env.DB.prepare(
      "UPDATE shares SET status = ?, drafts = NULL, error = NULL, updated = ? WHERE id = ?"
    )
      .bind(status, now, id)
      .run();
  } else {
    await env.DB.prepare("UPDATE shares SET status = ?, updated = ? WHERE id = ?")
      .bind(status, now, id)
      .run();
  }
}

async function dbDeleteShare(env, id) {
  await env.DB.prepare("DELETE FROM shares WHERE id = ?").bind(id).run();
}

async function dbClaimShare(env, now) {
  const staleBefore = now - CLAIM_STALE_MS;
  const row = await env.DB.prepare(
    "SELECT * FROM shares WHERE status = 'new' OR (status = 'drafting' AND updated < ?) ORDER BY created ASC LIMIT 1"
  )
    .bind(staleBefore)
    .first();
  if (!row) return null;
  await env.DB.prepare("UPDATE shares SET status = 'drafting', updated = ? WHERE id = ?")
    .bind(now, row.id)
    .run();
  row.status = "drafting";
  row.updated = now;
  return row;
}

async function dbSetDrafts(env, id, drafts, now) {
  await env.DB.prepare(
    "UPDATE shares SET status = 'drafted', drafts = ?, error = NULL, updated = ? WHERE id = ?"
  )
    .bind(JSON.stringify(drafts), now, id)
    .run();
}

async function dbSetFailed(env, id, error, now) {
  await env.DB.prepare(
    "UPDATE shares SET status = 'failed', drafts = NULL, error = ?, updated = ? WHERE id = ?"
  )
    .bind(error, now, id)
    .run();
}

async function dbGetAllRules(env) {
  const result = await env.DB.prepare("SELECT sub, rules FROM rules").all();
  const out = {};
  for (const row of result.results || []) {
    out[row.sub] = JSON.parse(row.rules);
  }
  return out;
}

async function dbUpsertRules(env, sub, rules, now) {
  const update = await env.DB.prepare("UPDATE rules SET rules = ?, updated = ? WHERE sub = ?")
    .bind(JSON.stringify(rules), now, sub)
    .run();
  const changed = update.meta && typeof update.meta.changes === "number" ? update.meta.changes : 0;
  if (changed === 0) {
    await env.DB.prepare("INSERT INTO rules (sub, rules, updated) VALUES (?, ?, ?)")
      .bind(sub, JSON.stringify(rules), now)
      .run();
  }
}

// ---- db helpers: items, events, kv (SPEC-v2.md) ----

// The worker has no timezone config of its own; "today" is derived from the
// data the engine already writes (it stamps each item with the day it
// belongs to, in its own timezone). Taking the latest day seen across all
// items keeps the worker in step with the engine without needing to know
// its offset. Noted in SPEC-v2.md as the smallest compatible clarification.
async function dbCurrentDay(env) {
  const row = await env.DB.prepare("SELECT MAX(day) as day FROM items").first();
  if (row && row.day) return row.day;
  return new Date().toISOString().slice(0, 10);
}

async function dbGetItem(env, id) {
  const row = await env.DB.prepare("SELECT * FROM items WHERE id = ?").bind(id).first();
  return row || null;
}

async function dbOpenItems(env, platform, queue) {
  const result = await env.DB.prepare(
    "SELECT * FROM items WHERE platform = ? AND queue = ? AND status = 'open' ORDER BY created ASC"
  )
    .bind(platform, queue)
    .all();
  return result.results || [];
}

async function dbCountItems(env, platform, queue, status, day) {
  const row = await env.DB.prepare(
    "SELECT COUNT(*) as c FROM items WHERE platform = ? AND queue = ? AND status = ? AND day = ?"
  )
    .bind(platform, queue, status, day)
    .first();
  return row ? row.c : 0;
}

async function dbListItems(env, { status, day, limit }) {
  let result;
  if (status && day) {
    result = await env.DB.prepare(
      "SELECT * FROM items WHERE status = ? AND day = ? ORDER BY updated DESC LIMIT ?"
    )
      .bind(status, day, limit)
      .all();
  } else if (status) {
    result = await env.DB.prepare(
      "SELECT * FROM items WHERE status = ? ORDER BY updated DESC LIMIT ?"
    )
      .bind(status, limit)
      .all();
  } else if (day) {
    result = await env.DB.prepare(
      "SELECT * FROM items WHERE day = ? ORDER BY updated DESC LIMIT ?"
    )
      .bind(day, limit)
      .all();
  } else {
    result = await env.DB.prepare("SELECT * FROM items ORDER BY updated DESC LIMIT ?")
      .bind(limit)
      .all();
  }
  return result.results || [];
}

async function dbInsertItem(env, item, now) {
  await env.DB.prepare(
    "INSERT INTO items (id, platform, queue, status, title, body, url, target, why, source, photos, day, created, updated, link, skip_reason, skip_note, extra) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
  )
    .bind(
      item.id,
      item.platform,
      item.queue,
      item.status || "open",
      item.title ?? null,
      item.body ?? null,
      item.url ?? null,
      item.target ?? null,
      item.why ?? null,
      item.source ?? null,
      JSON.stringify(item.photos || []),
      item.day ?? null,
      now,
      now,
      item.link ?? null,
      item.skip_reason ?? null,
      item.skip_note ?? null,
      item.extra !== undefined && item.extra !== null ? JSON.stringify(item.extra) : null
    )
    .run();
}

// Upserts one item. If the row already exists and the app has already
// finished it (done/skipped), the engine may still refresh the describing
// fields, but status/link/skip_reason/skip_note stay exactly what the app
// set: the worker never resurrects a finished item back to open.
async function dbUpsertItem(env, item, existing, now) {
  if (!existing) {
    await dbInsertItem(env, item, now);
    return;
  }

  const photos = JSON.stringify(item.photos || []);
  const extra = item.extra !== undefined && item.extra !== null ? JSON.stringify(item.extra) : null;
  const day = item.day ?? existing.day;

  if (existing.status === "done" || existing.status === "skipped") {
    await env.DB.prepare(
      "UPDATE items SET platform = ?, queue = ?, title = ?, body = ?, url = ?, target = ?, why = ?, source = ?, photos = ?, day = ?, updated = ?, extra = ? WHERE id = ?"
    )
      .bind(
        item.platform,
        item.queue,
        item.title ?? null,
        item.body ?? null,
        item.url ?? null,
        item.target ?? null,
        item.why ?? null,
        item.source ?? null,
        photos,
        day,
        now,
        extra,
        item.id
      )
      .run();
    return;
  }

  const status = item.status || existing.status;
  await env.DB.prepare(
    "UPDATE items SET platform = ?, queue = ?, status = ?, title = ?, body = ?, url = ?, target = ?, why = ?, source = ?, photos = ?, day = ?, updated = ?, link = ?, skip_reason = ?, skip_note = ?, extra = ? WHERE id = ?"
  )
    .bind(
      item.platform,
      item.queue,
      status,
      item.title ?? null,
      item.body ?? null,
      item.url ?? null,
      item.target ?? null,
      item.why ?? null,
      item.source ?? null,
      photos,
      day,
      now,
      item.link ?? null,
      item.skip_reason ?? null,
      item.skip_note ?? null,
      extra,
      item.id
    )
    .run();
}

async function dbInsertEvent(env, item, kind, link, reason, note, at) {
  await env.DB.prepare(
    "INSERT INTO events (item, kind, link, reason, note, at) VALUES (?, ?, ?, ?, ?, ?)"
  )
    .bind(item, kind, link ?? null, reason ?? null, note ?? null, at)
    .run();
}

async function dbListEvents(env, after, limit) {
  const result = await env.DB.prepare(
    "SELECT * FROM events WHERE seq > ? ORDER BY seq ASC LIMIT ?"
  )
    .bind(after, limit)
    .all();
  return result.results || [];
}

async function dbGetKv(env, k) {
  const row = await env.DB.prepare("SELECT v FROM kv WHERE k = ?").bind(k).first();
  return row ? row.v : null;
}

async function dbSetKv(env, k, v, now) {
  await env.DB.prepare(
    "INSERT INTO kv (k, v, updated) VALUES (?, ?, ?) ON CONFLICT(k) DO UPDATE SET v = excluded.v, updated = excluded.updated"
  )
    .bind(k, v, now)
    .run();
}

// ---- route handlers ----

async function handleHealth() {
  return jsonResponse({ ok: true });
}

async function handleCreateShare(request, env) {
  let form;
  try {
    form = await request.formData();
  } catch {
    return errorResponse("expected multipart/form-data", 400);
  }

  const noteValue = form.get("note");
  let note = null;
  if (typeof noteValue === "string" && noteValue.length > 0) {
    if (noteValue.length > MAX_NOTE_CHARS) {
      return errorResponse(`note must be at most ${MAX_NOTE_CHARS} chars`, 400);
    }
    note = noteValue;
  }

  const photoEntries = form.getAll("photo").filter((entry) => entry && typeof entry !== "string");
  if (photoEntries.length < 1 || photoEntries.length > MAX_PHOTOS) {
    return errorResponse(`expected 1 to ${MAX_PHOTOS} photo files`, 400);
  }
  for (const file of photoEntries) {
    if (file.type && file.type !== "image/jpeg") {
      return errorResponse("photo must be image/jpeg", 400);
    }
    if (file.size > MAX_PHOTO_BYTES) {
      return errorResponse(`photo must be at most ${MAX_PHOTO_BYTES} bytes`, 400);
    }
  }

  const id = newId();
  const now = Date.now();
  const photoKeys = [];
  let index = 0;
  for (const file of photoEntries) {
    const key = `${id}/${index}.jpg`;
    const buf = await file.arrayBuffer();
    await env.PHOTOS.put(key, buf, { httpMetadata: { contentType: "image/jpeg" } });
    photoKeys.push(key);
    index += 1;
  }

  const share = {
    id,
    note,
    photos: photoKeys,
    status: "new",
    drafts: null,
    error: null,
    created: now,
    updated: now,
  };
  await dbInsertShare(env, share);

  return jsonResponse({ id }, 201);
}

async function handleListShares(request, env) {
  const now = Date.now();
  await dbCleanupOld(env, now);
  const rows = await dbListShares(env, MAX_SHARES_RETURNED);
  return jsonResponse({ shares: rows.map(rowToShare) });
}

async function handleUpdateStatus(request, env, id) {
  let body;
  try {
    body = await request.json();
  } catch {
    return errorResponse("expected JSON body", 400);
  }
  const status = body && body.status;
  if (status !== "posted" && status !== "skipped" && status !== "new") {
    return errorResponse('status must be "posted", "skipped" or "new"', 400);
  }
  const existing = await dbGetShare(env, id);
  if (!existing) return errorResponse("not found", 404);

  const now = Date.now();
  await dbUpdateStatus(env, id, status, now);
  const updated = await dbGetShare(env, id);
  return jsonResponse(rowToShare(updated));
}

async function handleDeleteShare(request, env, id) {
  const existing = await dbGetShare(env, id);
  if (!existing) return errorResponse("not found", 404);

  const photos = existing.photos ? JSON.parse(existing.photos) : [];
  for (const key of photos) {
    await env.PHOTOS.delete(key);
  }
  await dbDeleteShare(env, id);
  return jsonResponse({ deleted: true });
}

async function handleClaim(request, env) {
  const now = Date.now();
  const row = await dbClaimShare(env, now);
  if (!row) return new Response(null, { status: 204 });
  return jsonResponse(rowToShare(row));
}

async function handleSetDrafts(request, env, id) {
  let body;
  try {
    body = await request.json();
  } catch {
    return errorResponse("expected JSON body", 400);
  }
  const existing = await dbGetShare(env, id);
  if (!existing) return errorResponse("not found", 404);

  const now = Date.now();
  if (Array.isArray(body.drafts)) {
    await dbSetDrafts(env, id, body.drafts, now);
    await createPhotoItems(env, existing, body.drafts, now);
  } else if (typeof body.error === "string") {
    await dbSetFailed(env, id, body.error, now);
  } else {
    return errorResponse("expected drafts array or error string", 400);
  }
  const updated = await dbGetShare(env, id);
  return jsonResponse(rowToShare(updated));
}

// SPEC-v2.md: drafted photo shares become reddit/post items, one per draft,
// id "photo-<share>-<n>", so they show up in the post queue like anything
// else the engine fills in.
async function createPhotoItems(env, share, drafts, now) {
  const day = await dbCurrentDay(env);
  const photos = share.photos ? JSON.parse(share.photos) : [];
  for (let n = 0; n < drafts.length; n += 1) {
    const draft = drafts[n];
    const id = `photo-${share.id}-${n}`;
    const existing = await dbGetItem(env, id);
    const item = {
      id,
      platform: "reddit",
      queue: "post",
      status: "open",
      title: draft.title ?? null,
      body: draft.body ?? null,
      url: null,
      target: draft.sub ?? null,
      why: draft.why ?? null,
      source: "photo",
      photos,
      day,
      link: null,
      skip_reason: null,
      skip_note: null,
      extra: { rules_checked: draft.rules_checked ?? null, rule_notes: draft.rule_notes ?? null },
    };
    await dbUpsertItem(env, item, existing, now);
  }
}

async function handlePutRules(request, env) {
  let body;
  try {
    body = await request.json();
  } catch {
    return errorResponse("expected JSON body", 400);
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return errorResponse("expected an object of sub -> rules", 400);
  }
  const now = Date.now();
  for (const [sub, rules] of Object.entries(body)) {
    if (!Array.isArray(rules) || !rules.every((rule) => typeof rule === "string")) {
      return errorResponse(`rules for ${sub} must be an array of strings`, 400);
    }
    await dbUpsertRules(env, sub, rules, now);
  }
  return jsonResponse({ ok: true });
}

async function handleGetRules(request, env) {
  const rules = await dbGetAllRules(env);
  return jsonResponse(rules);
}

async function handleGetQueues(request, env) {
  const day = await dbCurrentDay(env);
  const targets = queueTargets(env);
  const platforms = {};
  for (const platform of PLATFORMS) {
    platforms[platform] = {};
    for (const queue of QUEUES) {
      const open = await dbOpenItems(env, platform, queue);
      const doneToday = await dbCountItems(env, platform, queue, "done", day);
      const skippedToday = await dbCountItems(env, platform, queue, "skipped", day);
      platforms[platform][queue] = {
        open: open.map(rowToItem),
        done_today: doneToday,
        skipped_today: skippedToday,
        target: targets[queue],
      };
    }
  }
  return jsonResponse({ day, platforms });
}

// GET /v1/items: shared by the app (history, e.g. ?status=done&limit=50)
// and the engine (reconciliation, e.g. ?status=open or ?day=...).
async function handleGetItems(request, env, url) {
  const status = url.searchParams.get("status");
  const day = url.searchParams.get("day");
  let limit = parseInt(url.searchParams.get("limit") || "", 10);
  if (!Number.isFinite(limit) || limit <= 0) limit = DEFAULT_ITEMS_LIMIT;
  if (limit > MAX_ITEMS_RETURNED) limit = MAX_ITEMS_RETURNED;
  const rows = await dbListItems(env, { status, day, limit });
  return jsonResponse({ items: rows.map(rowToItem) });
}

async function handlePutItems(request, env) {
  let body;
  try {
    body = await request.json();
  } catch {
    return errorResponse("expected JSON body", 400);
  }
  if (!body || !Array.isArray(body.items)) {
    return errorResponse("expected an items array", 400);
  }
  const now = Date.now();
  for (const item of body.items) {
    if (!item || typeof item.id !== "string" || !item.id) {
      return errorResponse("each item needs an id", 400);
    }
    if (!PLATFORMS.includes(item.platform)) {
      return errorResponse(`platform must be one of ${PLATFORMS.join(", ")}`, 400);
    }
    if (!QUEUES.includes(item.queue)) {
      return errorResponse(`queue must be one of ${QUEUES.join(", ")}`, 400);
    }
    const existing = await dbGetItem(env, item.id);
    await dbUpsertItem(env, item, existing, now);
  }
  return jsonResponse({ ok: true });
}

async function handleItemDone(request, env, id) {
  let body = {};
  try {
    const text = await request.text();
    if (text) body = JSON.parse(text);
  } catch {
    return errorResponse("expected JSON body", 400);
  }
  const existing = await dbGetItem(env, id);
  if (!existing) return errorResponse("not found", 404);

  const now = Date.now();
  const link = typeof body.link === "string" && body.link.length > 0 ? body.link : existing.link ?? null;
  await env.DB.prepare("UPDATE items SET status = 'done', link = ?, updated = ? WHERE id = ?")
    .bind(link, now, id)
    .run();
  await dbInsertEvent(env, id, "done", link, null, null, now);
  const updated = await dbGetItem(env, id);
  return jsonResponse(rowToItem(updated));
}

async function handleItemSkip(request, env, id) {
  let body;
  try {
    body = await request.json();
  } catch {
    return errorResponse("expected JSON body", 400);
  }
  const reason = body && body.reason;
  if (reason !== "bad" && reason !== "later") {
    return errorResponse('reason must be "bad" or "later"', 400);
  }
  const note = typeof body.note === "string" ? body.note : null;
  const existing = await dbGetItem(env, id);
  if (!existing) return errorResponse("not found", 404);

  const now = Date.now();
  await env.DB.prepare(
    "UPDATE items SET status = 'skipped', skip_reason = ?, skip_note = ?, updated = ? WHERE id = ?"
  )
    .bind(reason, note, now, id)
    .run();
  await dbInsertEvent(env, id, "skip", null, reason, note, now);
  const updated = await dbGetItem(env, id);
  return jsonResponse(rowToItem(updated));
}

async function handleItemLink(request, env, id) {
  let body;
  try {
    body = await request.json();
  } catch {
    return errorResponse("expected JSON body", 400);
  }
  const link = body && body.link;
  if (typeof link !== "string" || link.length === 0) {
    return errorResponse("expected a link string", 400);
  }
  const existing = await dbGetItem(env, id);
  if (!existing) return errorResponse("not found", 404);

  const now = Date.now();
  await env.DB.prepare("UPDATE items SET link = ?, updated = ? WHERE id = ?").bind(link, now, id).run();
  await dbInsertEvent(env, id, "link", link, null, null, now);
  const updated = await dbGetItem(env, id);
  return jsonResponse(rowToItem(updated));
}

async function handleGetEvents(request, env, url) {
  let after = parseInt(url.searchParams.get("after") || "", 10);
  if (!Number.isFinite(after) || after < 0) after = 0;
  const rows = await dbListEvents(env, after, MAX_EVENTS_RETURNED);
  const last = rows.length > 0 ? rows[rows.length - 1].seq : after;
  return jsonResponse({ events: rows.map(rowToEvent), last });
}

async function handleGetGrowth(request, env) {
  const value = await dbGetKv(env, "growth");
  return jsonResponse(value ? JSON.parse(value) : {});
}

async function handlePutGrowth(request, env) {
  let body;
  try {
    body = await request.json();
  } catch {
    return errorResponse("expected JSON body", 400);
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return errorResponse("expected a JSON object", 400);
  }
  await dbSetKv(env, "growth", JSON.stringify(body), Date.now());
  return jsonResponse({ ok: true });
}

async function handleGetPhoto(request, env, key) {
  const object = await env.PHOTOS.get(key);
  if (!object) return errorResponse("not found", 404);
  const contentType =
    (object.httpMetadata && object.httpMetadata.contentType) || "image/jpeg";
  return new Response(object.body, {
    status: 200,
    headers: { "content-type": contentType },
  });
}

// ---- router ----

function matchPhotoKey(pathname) {
  const prefix = "/v1/photos/";
  if (!pathname.startsWith(prefix)) return null;
  const rest = pathname.slice(prefix.length);
  return rest ? decodeURIComponent(rest) : null;
}

function matchSharesId(pathname, suffix) {
  const prefix = "/v1/shares/";
  if (!pathname.startsWith(prefix) || !pathname.endsWith(suffix)) return null;
  const middle = pathname.slice(prefix.length, pathname.length - suffix.length);
  return middle || null;
}

function matchItemsId(pathname, suffix) {
  const prefix = "/v1/items/";
  if (!pathname.startsWith(prefix) || !pathname.endsWith(suffix)) return null;
  const middle = pathname.slice(prefix.length, pathname.length - suffix.length);
  return middle || null;
}

async function router(request, env) {
  const url = new URL(request.url);
  const { pathname } = url;
  const method = request.method;

  if (method === "GET" && pathname === "/health") {
    return handleHealth();
  }

  if (method === "POST" && pathname === "/v1/shares") {
    if (!checkAuth(request, env, ["app"])) return errorResponse("unauthorized", 401);
    return handleCreateShare(request, env);
  }

  if (method === "GET" && pathname === "/v1/shares") {
    if (!checkAuth(request, env, ["app"])) return errorResponse("unauthorized", 401);
    return handleListShares(request, env);
  }

  const statusId = matchSharesId(pathname, "/status");
  if (method === "POST" && statusId) {
    if (!checkAuth(request, env, ["app"])) return errorResponse("unauthorized", 401);
    return handleUpdateStatus(request, env, statusId);
  }

  const draftsId = matchSharesId(pathname, "/drafts");
  if (method === "POST" && draftsId) {
    if (!checkAuth(request, env, ["drafter"])) return errorResponse("unauthorized", 401);
    return handleSetDrafts(request, env, draftsId);
  }

  if (method === "DELETE" && pathname.startsWith("/v1/shares/")) {
    const id = pathname.slice("/v1/shares/".length);
    if (id && !id.includes("/")) {
      if (!checkAuth(request, env, ["app"])) return errorResponse("unauthorized", 401);
      return handleDeleteShare(request, env, id);
    }
  }

  if (method === "POST" && pathname === "/v1/claim") {
    if (!checkAuth(request, env, ["drafter"])) return errorResponse("unauthorized", 401);
    return handleClaim(request, env);
  }

  if (method === "PUT" && pathname === "/v1/rules") {
    if (!checkAuth(request, env, ["drafter"])) return errorResponse("unauthorized", 401);
    return handlePutRules(request, env);
  }

  if (method === "GET" && pathname === "/v1/rules") {
    if (!checkAuth(request, env, ["drafter"])) return errorResponse("unauthorized", 401);
    return handleGetRules(request, env);
  }

  const photoKey = matchPhotoKey(pathname);
  if (method === "GET" && photoKey) {
    if (!checkAuth(request, env, ["app", "drafter"])) return errorResponse("unauthorized", 401);
    return handleGetPhoto(request, env, photoKey);
  }

  // ---- SPEC-v2.md: queues, items, events, growth ----

  if (method === "GET" && pathname === "/v1/queues") {
    if (!checkAuth(request, env, ["app"])) return errorResponse("unauthorized", 401);
    return handleGetQueues(request, env);
  }

  if (method === "GET" && pathname === "/v1/items") {
    if (!checkAuth(request, env, ["app", "engine"])) return errorResponse("unauthorized", 401);
    return handleGetItems(request, env, url);
  }

  if (method === "PUT" && pathname === "/v1/items") {
    if (!checkAuth(request, env, ["engine"])) return errorResponse("unauthorized", 401);
    return handlePutItems(request, env);
  }

  const doneId = matchItemsId(pathname, "/done");
  if (method === "POST" && doneId) {
    if (!checkAuth(request, env, ["app"])) return errorResponse("unauthorized", 401);
    return handleItemDone(request, env, doneId);
  }

  const skipId = matchItemsId(pathname, "/skip");
  if (method === "POST" && skipId) {
    if (!checkAuth(request, env, ["app"])) return errorResponse("unauthorized", 401);
    return handleItemSkip(request, env, skipId);
  }

  const linkId = matchItemsId(pathname, "/link");
  if (method === "POST" && linkId) {
    if (!checkAuth(request, env, ["app"])) return errorResponse("unauthorized", 401);
    return handleItemLink(request, env, linkId);
  }

  if (method === "GET" && pathname === "/v1/growth") {
    if (!checkAuth(request, env, ["app"])) return errorResponse("unauthorized", 401);
    return handleGetGrowth(request, env);
  }

  if (method === "PUT" && pathname === "/v1/growth") {
    if (!checkAuth(request, env, ["engine"])) return errorResponse("unauthorized", 401);
    return handlePutGrowth(request, env);
  }

  if (method === "GET" && pathname === "/v1/events") {
    if (!checkAuth(request, env, ["engine"])) return errorResponse("unauthorized", 401);
    return handleGetEvents(request, env, url);
  }

  return errorResponse("not found", 404);
}

export default {
  async fetch(request, env) {
    try {
      return await router(request, env);
    } catch (err) {
      return errorResponse(`internal error: ${err && err.message ? err.message : String(err)}`, 500);
    }
  },
};

// Exported for tests.
export { router, rowToShare, rowToItem, rowToEvent };
