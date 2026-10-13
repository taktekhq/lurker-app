// Cloudflare Worker for lurker-app. Plain JS module, no build step.
//
// Bindings expected (see wrangler-style metadata in deploy.sh):
//   R2 bucket   PHOTOS
//   D1 database DB
//   secret text APP_TOKEN
//   secret text DRAFTER_TOKEN
//
// Routes are documented in SPEC.md at the repo root.

const MAX_PHOTOS = 10;
const MAX_PHOTO_BYTES = 5 * 1024 * 1024;
const MAX_NOTE_CHARS = 2000;
const MAX_SHARES_RETURNED = 100;
const CLAIM_STALE_MS = 15 * 60 * 1000;
const POSTED_RETENTION_MS = 30 * 24 * 60 * 60 * 1000;
const STATUSES = new Set(["new", "drafting", "drafted", "failed", "posted", "skipped"]);

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

// ---- auth ----

function bearerToken(request) {
  const header = request.headers.get("Authorization") || "";
  const match = /^Bearer (.+)$/.exec(header);
  return match ? match[1] : null;
}

// kinds is an array containing any of "app", "drafter"
function checkAuth(request, env, kinds) {
  const token = bearerToken(request);
  if (!token) return false;
  if (kinds.includes("app") && env.APP_TOKEN && token === env.APP_TOKEN) return true;
  if (kinds.includes("drafter") && env.DRAFTER_TOKEN && token === env.DRAFTER_TOKEN) return true;
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
  } else if (typeof body.error === "string") {
    await dbSetFailed(env, id, body.error, now);
  } else {
    return errorResponse("expected drafts array or error string", 400);
  }
  const updated = await dbGetShare(env, id);
  return jsonResponse(rowToShare(updated));
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
export { router, rowToShare };
