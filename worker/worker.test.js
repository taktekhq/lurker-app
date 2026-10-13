import test from "node:test";
import assert from "node:assert/strict";
import worker from "./worker.js";
import { makeEnv } from "./test-helpers.js";

const APP = "test-app-token";
const DRAFTER = "test-drafter-token";

function req(method, path, { token, body, headers } = {}) {
  const h = new Headers(headers || {});
  if (token) h.set("Authorization", `Bearer ${token}`);
  let finalBody = body;
  if (body && typeof body === "object" && !(body instanceof FormData)) {
    finalBody = JSON.stringify(body);
    h.set("content-type", "application/json");
  }
  return new Request(`https://worker.example${path}`, { method, headers: h, body: finalBody });
}

function jpegBlob(size = 10) {
  return new Blob([new Uint8Array(size).fill(1)], { type: "image/jpeg" });
}

async function createShare(env, { note, photoCount = 1 } = {}) {
  const form = new FormData();
  if (note !== undefined) form.append("note", note);
  for (let i = 0; i < photoCount; i += 1) {
    form.append("photo", jpegBlob(), `photo${i}.jpg`);
  }
  const res = await worker.fetch(req("POST", "/v1/shares", { token: APP, body: form }), env);
  return res;
}

test("health needs no auth", async () => {
  const env = makeEnv();
  const res = await worker.fetch(req("GET", "/health"), env);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { ok: true });
});

test("protected route with no token is 401", async () => {
  const env = makeEnv();
  const res = await worker.fetch(req("GET", "/v1/shares"), env);
  assert.equal(res.status, 401);
});

test("protected route with wrong token is 401", async () => {
  const env = makeEnv();
  const res = await worker.fetch(req("GET", "/v1/shares", { token: "nope" }), env);
  assert.equal(res.status, 401);
});

test("drafter token cannot call app routes", async () => {
  const env = makeEnv();
  const res = await worker.fetch(req("GET", "/v1/shares", { token: DRAFTER }), env);
  assert.equal(res.status, 401);
});

test("create share stores note, photos and a new row", async () => {
  const env = makeEnv();
  const res = await createShare(env, { note: "took the scrambler out" });
  assert.equal(res.status, 201);
  const { id } = await res.json();
  assert.ok(id);

  const list = await worker.fetch(req("GET", "/v1/shares", { token: APP }), env);
  const { shares } = await list.json();
  assert.equal(shares.length, 1);
  assert.equal(shares[0].id, id);
  assert.equal(shares[0].note, "took the scrambler out");
  assert.equal(shares[0].status, "new");
  assert.equal(shares[0].photos.length, 1);
  assert.equal(env.PHOTOS.objects.size, 1);
});

test("create share without a note is allowed", async () => {
  const env = makeEnv();
  const res = await createShare(env, { photoCount: 2 });
  assert.equal(res.status, 201);
});

test("create share rejects zero photos", async () => {
  const env = makeEnv();
  const form = new FormData();
  form.append("note", "no photos");
  const res = await worker.fetch(req("POST", "/v1/shares", { token: APP, body: form }), env);
  assert.equal(res.status, 400);
});

test("create share rejects more than 10 photos", async () => {
  const env = makeEnv();
  const res = await createShare(env, { photoCount: 11 });
  assert.equal(res.status, 400);
});

test("create share rejects a non-jpeg file", async () => {
  const env = makeEnv();
  const form = new FormData();
  form.append("photo", new Blob([new Uint8Array(4)], { type: "image/png" }), "a.png");
  const res = await worker.fetch(req("POST", "/v1/shares", { token: APP, body: form }), env);
  assert.equal(res.status, 400);
});

test("create share rejects an oversized photo", async () => {
  const env = makeEnv();
  const form = new FormData();
  form.append("photo", jpegBlob(5 * 1024 * 1024 + 1), "big.jpg");
  const res = await worker.fetch(req("POST", "/v1/shares", { token: APP, body: form }), env);
  assert.equal(res.status, 400);
});

test("create share rejects a note over 2000 chars", async () => {
  const env = makeEnv();
  const res = await createShare(env, { note: "a".repeat(2001) });
  assert.equal(res.status, 400);
});

test("list shares is newest first and drops old posted/skipped rows", async () => {
  const env = makeEnv();
  const now = Date.now();
  const THIRTY_ONE_DAYS = 31 * 24 * 60 * 60 * 1000;
  env.DB.tables.shares.push(
    { id: "old-posted", note: null, photos: "[]", status: "posted", drafts: null, error: null, created: now - THIRTY_ONE_DAYS, updated: now - THIRTY_ONE_DAYS },
    { id: "recent", note: null, photos: "[]", status: "new", drafts: null, error: null, created: now - 1000, updated: now - 1000 },
    { id: "newest", note: null, photos: "[]", status: "new", drafts: null, error: null, created: now, updated: now }
  );

  const res = await worker.fetch(req("GET", "/v1/shares", { token: APP }), env);
  const { shares } = await res.json();
  assert.deepEqual(shares.map((s) => s.id), ["newest", "recent"]);
});

test("update status to posted, skipped, then new", async () => {
  const env = makeEnv();
  const createRes = await createShare(env);
  const { id } = await createRes.json();

  const posted = await worker.fetch(
    req("POST", `/v1/shares/${id}/status`, { token: APP, body: { status: "posted" } }),
    env
  );
  assert.equal(posted.status, 200);
  assert.equal((await posted.json()).status, "posted");

  const redo = await worker.fetch(
    req("POST", `/v1/shares/${id}/status`, { token: APP, body: { status: "new" } }),
    env
  );
  const redoBody = await redo.json();
  assert.equal(redoBody.status, "new");
  assert.equal(redoBody.drafts.length, 0);
});

test("update status rejects an invalid value", async () => {
  const env = makeEnv();
  const createRes = await createShare(env);
  const { id } = await createRes.json();
  const res = await worker.fetch(
    req("POST", `/v1/shares/${id}/status`, { token: APP, body: { status: "whatever" } }),
    env
  );
  assert.equal(res.status, 400);
});

test("update status on a missing share is 404", async () => {
  const env = makeEnv();
  const res = await worker.fetch(
    req("POST", "/v1/shares/does-not-exist/status", { token: APP, body: { status: "posted" } }),
    env
  );
  assert.equal(res.status, 404);
});

test("delete share removes the row and its photos", async () => {
  const env = makeEnv();
  const createRes = await createShare(env, { photoCount: 2 });
  const { id } = await createRes.json();
  assert.equal(env.PHOTOS.objects.size, 2);

  const del = await worker.fetch(req("DELETE", `/v1/shares/${id}`, { token: APP }), env);
  assert.equal(del.status, 200);
  assert.equal(env.PHOTOS.objects.size, 0);

  const again = await worker.fetch(req("DELETE", `/v1/shares/${id}`, { token: APP }), env);
  assert.equal(again.status, 404);
});

test("claim returns 204 when there is nothing new", async () => {
  const env = makeEnv();
  const res = await worker.fetch(req("POST", "/v1/claim", { token: DRAFTER }), env);
  assert.equal(res.status, 204);
});

test("claim takes the oldest new share and marks it drafting", async () => {
  const env = makeEnv();
  await createShare(env, { note: "first" });
  await createShare(env, { note: "second" });

  const claim1 = await worker.fetch(req("POST", "/v1/claim", { token: DRAFTER }), env);
  assert.equal(claim1.status, 200);
  const share1 = await claim1.json();
  assert.equal(share1.note, "first");
  assert.equal(share1.status, "drafting");

  const claim2 = await worker.fetch(req("POST", "/v1/claim", { token: DRAFTER }), env);
  const share2 = await claim2.json();
  assert.equal(share2.note, "second");
});

test("claim picks up a share stuck drafting for more than 15 minutes", async () => {
  const env = makeEnv();
  const now = Date.now();
  env.DB.tables.shares.push({
    id: "stale",
    note: "stuck",
    photos: "[]",
    status: "drafting",
    drafts: null,
    error: null,
    created: now - 1000,
    updated: now - 16 * 60 * 1000,
  });

  const res = await worker.fetch(req("POST", "/v1/claim", { token: DRAFTER }), env);
  assert.equal(res.status, 200);
  const share = await res.json();
  assert.equal(share.id, "stale");
});

test("app token cannot claim", async () => {
  const env = makeEnv();
  const res = await worker.fetch(req("POST", "/v1/claim", { token: APP }), env);
  assert.equal(res.status, 401);
});

test("drafter posts drafts back", async () => {
  const env = makeEnv();
  const createRes = await createShare(env);
  const { id } = await createRes.json();
  await worker.fetch(req("POST", "/v1/claim", { token: DRAFTER }), env);

  const drafts = [
    { sub: "Ducati", title: "scrambler morning ride", body: "", why: "his bike", rules_checked: true, rule_notes: "" },
  ];
  const res = await worker.fetch(
    req("POST", `/v1/shares/${id}/drafts`, { token: DRAFTER, body: { drafts } }),
    env
  );
  assert.equal(res.status, 200);
  const share = await res.json();
  assert.equal(share.status, "drafted");
  assert.equal(share.drafts.length, 1);
});

test("drafter posts an error and the share is marked failed", async () => {
  const env = makeEnv();
  const createRes = await createShare(env);
  const { id } = await createRes.json();

  const res = await worker.fetch(
    req("POST", `/v1/shares/${id}/drafts`, { token: DRAFTER, body: { error: "model timed out" } }),
    env
  );
  assert.equal(res.status, 200);
  const share = await res.json();
  assert.equal(share.status, "failed");
  assert.equal(share.error, "model timed out");
});

test("drafts route rejects a body with neither drafts nor error", async () => {
  const env = makeEnv();
  const createRes = await createShare(env);
  const { id } = await createRes.json();
  const res = await worker.fetch(req("POST", `/v1/shares/${id}/drafts`, { token: DRAFTER, body: {} }), env);
  assert.equal(res.status, 400);
});

test("app token cannot post drafts", async () => {
  const env = makeEnv();
  const createRes = await createShare(env);
  const { id } = await createRes.json();
  const res = await worker.fetch(
    req("POST", `/v1/shares/${id}/drafts`, { token: APP, body: { drafts: [] } }),
    env
  );
  assert.equal(res.status, 401);
});

test("rules: put then get round-trips, and updates in place", async () => {
  const env = makeEnv();
  const put1 = await worker.fetch(
    req("PUT", "/v1/rules", { token: DRAFTER, body: { Ducati: ["be nice", "no spam"] } }),
    env
  );
  assert.equal(put1.status, 200);

  const put2 = await worker.fetch(
    req("PUT", "/v1/rules", { token: DRAFTER, body: { Ducati: ["be nice"], motorcycles: ["flair required"] } }),
    env
  );
  assert.equal(put2.status, 200);

  const get = await worker.fetch(req("GET", "/v1/rules", { token: DRAFTER }), env);
  const rules = await get.json();
  assert.deepEqual(rules.Ducati, ["be nice"]);
  assert.deepEqual(rules.motorcycles, ["flair required"]);
});

test("rules rejects a non-array value", async () => {
  const env = makeEnv();
  const res = await worker.fetch(
    req("PUT", "/v1/rules", { token: DRAFTER, body: { Ducati: "not an array" } }),
    env
  );
  assert.equal(res.status, 400);
});

test("app token cannot read or write rules", async () => {
  const env = makeEnv();
  const res = await worker.fetch(req("GET", "/v1/rules", { token: APP }), env);
  assert.equal(res.status, 401);
});

test("photos: either token can fetch, missing key is 404", async () => {
  const env = makeEnv();
  const createRes = await createShare(env);
  const { id } = await createRes.json();
  const list = await worker.fetch(req("GET", "/v1/shares", { token: APP }), env);
  const { shares } = await list.json();
  const key = shares[0].photos[0];

  const appFetch = await worker.fetch(req("GET", `/v1/photos/${key}`, { token: APP }), env);
  assert.equal(appFetch.status, 200);
  assert.equal(appFetch.headers.get("content-type"), "image/jpeg");

  const drafterFetch = await worker.fetch(req("GET", `/v1/photos/${key}`, { token: DRAFTER }), env);
  assert.equal(drafterFetch.status, 200);

  const missing = await worker.fetch(req("GET", `/v1/photos/${id}/99.jpg`, { token: APP }), env);
  assert.equal(missing.status, 404);
});

test("photos route needs a valid token", async () => {
  const env = makeEnv();
  const res = await worker.fetch(req("GET", "/v1/photos/abc/0.jpg"), env);
  assert.equal(res.status, 401);
});

test("unknown route is 404", async () => {
  const env = makeEnv();
  const res = await worker.fetch(req("GET", "/v1/nope", { token: APP }), env);
  assert.equal(res.status, 404);
});
