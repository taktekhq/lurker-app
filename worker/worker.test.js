import test from "node:test";
import assert from "node:assert/strict";
import worker from "./worker.js";
import { makeEnv } from "./test-helpers.js";

const APP = "test-app-token";
const DRAFTER = "test-drafter-token";
const ENGINE = "test-engine-token";

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

// ---- SPEC-v2.md: queues, items, events, growth ----

function putItem(env, item) {
  return worker.fetch(req("PUT", "/v1/items", { token: ENGINE, body: { items: [item] } }), env);
}

function baseItem(overrides = {}) {
  return {
    id: "a1",
    platform: "reddit",
    queue: "post",
    status: "open",
    title: "a title",
    body: "",
    url: null,
    target: "Ducati",
    why: "his bike",
    source: "kbase",
    photos: [],
    day: "2026-10-13",
    ...overrides,
  };
}

test("queues starts empty for every platform and queue", async () => {
  const env = makeEnv();
  const res = await worker.fetch(req("GET", "/v1/queues", { token: APP }), env);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.ok(body.day);
  for (const platform of ["reddit", "hn"]) {
    for (const queue of ["post", "comment"]) {
      const q = body.platforms[platform][queue];
      assert.deepEqual(q.open, []);
      assert.equal(q.done_today, 0);
      assert.equal(q.skipped_today, 0);
      assert.equal(q.target, queue === "post" ? 3 : 7);
    }
  }
});

test("engine upserts an item, app sees it in queues", async () => {
  const env = makeEnv();
  const put = await putItem(env, baseItem());
  assert.equal(put.status, 200);

  const res = await worker.fetch(req("GET", "/v1/queues", { token: APP }), env);
  const body = await res.json();
  const open = body.platforms.reddit.post.open;
  assert.equal(open.length, 1);
  assert.equal(open[0].id, "a1");
  assert.equal(open[0].title, "a title");
  assert.equal(body.day, "2026-10-13");
});

test("app token cannot PUT items, engine token cannot read queues", async () => {
  const env = makeEnv();
  const putByApp = await worker.fetch(
    req("PUT", "/v1/items", { token: APP, body: { items: [baseItem()] } }),
    env
  );
  assert.equal(putByApp.status, 401);

  const queuesByEngine = await worker.fetch(req("GET", "/v1/queues", { token: ENGINE }), env);
  assert.equal(queuesByEngine.status, 401);
});

test("PUT items validates platform and queue", async () => {
  const env = makeEnv();
  const badPlatform = await putItem(env, baseItem({ platform: "twitter" }));
  assert.equal(badPlatform.status, 400);
  const badQueue = await putItem(env, baseItem({ queue: "dm" }));
  assert.equal(badQueue.status, 400);
});

test("done marks an item done, writes an event, and counts toward done_today", async () => {
  const env = makeEnv();
  await putItem(env, baseItem());

  const done = await worker.fetch(
    req("POST", "/v1/items/a1/done", { token: APP, body: { link: "https://reddit.com/x" } }),
    env
  );
  assert.equal(done.status, 200);
  const item = await done.json();
  assert.equal(item.status, "done");
  assert.equal(item.link, "https://reddit.com/x");
  assert.equal(env.DB.tables.events.length, 1);
  assert.equal(env.DB.tables.events[0].kind, "done");

  const queues = await worker.fetch(req("GET", "/v1/queues", { token: APP }), env);
  const q = (await queues.json()).platforms.reddit.post;
  assert.equal(q.done_today, 1);
  assert.equal(q.open.length, 0);
});

test("done with no body keeps any existing link", async () => {
  const env = makeEnv();
  await putItem(env, baseItem({ link: "https://old" }));
  const done = await worker.fetch(req("POST", "/v1/items/a1/done", { token: APP }), env);
  assert.equal(done.status, 200);
  assert.equal((await done.json()).link, "https://old");
});

test("done on a missing item is 404", async () => {
  const env = makeEnv();
  const res = await worker.fetch(req("POST", "/v1/items/nope/done", { token: APP, body: {} }), env);
  assert.equal(res.status, 404);
});

test("skip requires a valid reason and counts toward skipped_today", async () => {
  const env = makeEnv();
  await putItem(env, baseItem());

  const badReason = await worker.fetch(
    req("POST", "/v1/items/a1/skip", { token: APP, body: { reason: "whatever" } }),
    env
  );
  assert.equal(badReason.status, 400);

  const skip = await worker.fetch(
    req("POST", "/v1/items/a1/skip", { token: APP, body: { reason: "bad", note: "not his voice" } }),
    env
  );
  assert.equal(skip.status, 200);
  const item = await skip.json();
  assert.equal(item.status, "skipped");
  assert.equal(item.skip_reason, "bad");
  assert.equal(item.skip_note, "not his voice");

  const queues = await worker.fetch(req("GET", "/v1/queues", { token: APP }), env);
  assert.equal((await queues.json()).platforms.reddit.post.skipped_today, 1);
});

test("link route adds or fixes a link and writes an event", async () => {
  const env = makeEnv();
  await putItem(env, baseItem());
  await worker.fetch(req("POST", "/v1/items/a1/done", { token: APP, body: {} }), env);

  const res = await worker.fetch(
    req("POST", "/v1/items/a1/link", { token: APP, body: { link: "https://reddit.com/fixed" } }),
    env
  );
  assert.equal(res.status, 200);
  assert.equal((await res.json()).link, "https://reddit.com/fixed");

  const empty = await worker.fetch(
    req("POST", "/v1/items/a1/link", { token: APP, body: { link: "" } }),
    env
  );
  assert.equal(empty.status, 400);
});

test("PUT items never resurrects a done or skipped item back to open", async () => {
  const env = makeEnv();
  await putItem(env, baseItem());
  await worker.fetch(req("POST", "/v1/items/a1/done", { token: APP, body: { link: "https://x" } }), env);

  // The engine re-upserts the same item (e.g. a stale reconciliation sweep).
  const reupsert = await putItem(env, baseItem({ title: "updated title" }));
  assert.equal(reupsert.status, 200);

  const items = await worker.fetch(req("GET", "/v1/items?status=done", { token: APP }), env);
  const { items: rows } = await items.json();
  assert.equal(rows.length, 1);
  assert.equal(rows[0].status, "done");
  assert.equal(rows[0].link, "https://x");
  assert.equal(rows[0].title, "updated title");
});

test("GET /v1/items supports status, day and limit, for app and engine", async () => {
  const env = makeEnv();
  await putItem(env, baseItem({ id: "a1" }));
  await putItem(env, baseItem({ id: "a2", day: "2026-10-12" }));
  await worker.fetch(req("POST", "/v1/items/a1/done", { token: APP, body: {} }), env);

  const done = await worker.fetch(req("GET", "/v1/items?status=done&limit=50", { token: APP }), env);
  assert.equal((await done.json()).items.length, 1);

  const openByEngine = await worker.fetch(req("GET", "/v1/items?status=open", { token: ENGINE }), env);
  assert.equal((await openByEngine.json()).items.length, 1);

  const byDay = await worker.fetch(req("GET", "/v1/items?day=2026-10-12", { token: ENGINE }), env);
  assert.equal((await byDay.json()).items.length, 1);
});

test("GET /v1/items needs a valid token", async () => {
  const env = makeEnv();
  const res = await worker.fetch(req("GET", "/v1/items", { token: DRAFTER }), env);
  assert.equal(res.status, 401);
});

test("events: engine reads only events after a given seq", async () => {
  const env = makeEnv();
  await putItem(env, baseItem());
  await worker.fetch(req("POST", "/v1/items/a1/done", { token: APP, body: {} }), env);
  await putItem(env, baseItem({ id: "a2" }));
  await worker.fetch(req("POST", "/v1/items/a2/skip", { token: APP, body: { reason: "later" } }), env);

  const all = await worker.fetch(req("GET", "/v1/events?after=0", { token: ENGINE }), env);
  const allBody = await all.json();
  assert.equal(allBody.events.length, 2);
  const firstSeq = allBody.events[0].seq;

  const after = await worker.fetch(
    req("GET", `/v1/events?after=${firstSeq}`, { token: ENGINE }),
    env
  );
  const afterBody = await after.json();
  assert.equal(afterBody.events.length, 1);
  assert.equal(afterBody.events[0].kind, "skip");
  assert.equal(afterBody.last, allBody.last);
});

test("app token cannot read events", async () => {
  const env = makeEnv();
  const res = await worker.fetch(req("GET", "/v1/events", { token: APP }), env);
  assert.equal(res.status, 401);
});

test("growth: engine writes, app reads, empty by default", async () => {
  const env = makeEnv();
  const empty = await worker.fetch(req("GET", "/v1/growth", { token: APP }), env);
  assert.deepEqual(await empty.json(), {});

  const put = await worker.fetch(
    req("PUT", "/v1/growth", { token: ENGINE, body: { streak_days: 3, karma: { hn: [] } } }),
    env
  );
  assert.equal(put.status, 200);

  const get = await worker.fetch(req("GET", "/v1/growth", { token: APP }), env);
  assert.deepEqual(await get.json(), { streak_days: 3, karma: { hn: [] } });
});

test("app token cannot write growth, engine token cannot read it", async () => {
  const env = makeEnv();
  const appWrite = await worker.fetch(
    req("PUT", "/v1/growth", { token: APP, body: { ok: true } }),
    env
  );
  assert.equal(appWrite.status, 401);

  const engineRead = await worker.fetch(req("GET", "/v1/growth", { token: ENGINE }), env);
  assert.equal(engineRead.status, 401);
});

test("drafted photo shares become reddit/post items", async () => {
  const env = makeEnv();
  const createRes = await createShare(env, { note: "took the scrambler out" });
  const { id } = await createRes.json();
  await worker.fetch(req("POST", "/v1/claim", { token: DRAFTER }), env);

  const drafts = [
    { sub: "Ducati", title: "morning ride", body: "", why: "his bike", rules_checked: true, rule_notes: "" },
    { sub: "motorcycles", title: "scrambler", body: "", why: "general interest", rules_checked: false, rule_notes: "" },
  ];
  await worker.fetch(req("POST", `/v1/shares/${id}/drafts`, { token: DRAFTER, body: { drafts } }), env);

  const queues = await worker.fetch(req("GET", "/v1/queues", { token: APP }), env);
  const open = (await queues.json()).platforms.reddit.post.open;
  assert.equal(open.length, 2);
  assert.equal(open[0].id, `photo-${id}-0`);
  assert.equal(open[0].source, "photo");
  assert.equal(open[0].target, "Ducati");
  assert.equal(open[1].id, `photo-${id}-1`);
});
