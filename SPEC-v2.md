# Spec v2: queues

SPEC.md (photo shares) still holds. v2 adds what the app is mainly for: a **post queue** and a **comment queue** per platform (Reddit and Hacker News for now), filled by an engine that reads your notes, your recent work and live threads. You post everything yourself.

```
iPhone app ──> Worker (items, events, growth) <──> engine (any box; reads notes, HN, Reddit)
                                                     │ Reddit blocks most servers, so:
                                                     └──> chrome-fetch on a machine with a logged-in Chrome
```

## Queue rules

- Queues: `(platform, queue)` for platform `reddit | hn`, queue `post | comment`. Four queues.
- A day runs midnight to midnight in the engine's time zone (config).
- Each queue holds **5 open items** while fewer than 5 of that queue's items are `done` today. Once 5 are done, it holds **1** at a time.
- `done` and `skipped` items leave the queue. The engine refills gaps **within a few minutes of an action** (it polls events every minute; refill is debounced 2 minutes after the last action) and runs an **hourly sweep** that also expires comment items whose thread got too old and refills those.
- Skips carry a reason: `bad` (the suggestion was bad: the engine learns from these) or `later` (fine, just not now: the engine may offer it again on a later day if it is still fresh). Optional free-text note.
- Done carries an optional `link` to the post or comment. If it is missing, the engine looks for it (HN user items, Reddit user comments and posts) and fills it in.
- Photo shares (SPEC.md) that get drafted become `reddit/post` items with `source: "photo"` and their photo keys. They count toward the post queue like any other item.

## Worker additions

Tables:

```sql
items(id TEXT PRIMARY KEY, platform TEXT, queue TEXT, status TEXT,  -- open | done | skipped | expired
      title TEXT, body TEXT, url TEXT,   -- url: the thread to answer, or the submit page
      target TEXT,                        -- reddit: subreddit; hn: null
      why TEXT, source TEXT,              -- kbase | work | link | thread | photo
      photos TEXT,                        -- JSON array of R2 keys, photo items only
      day TEXT, created INTEGER, updated INTEGER,
      link TEXT, skip_reason TEXT, skip_note TEXT, extra TEXT)  -- extra: JSON, engine-owned
events(seq INTEGER PRIMARY KEY AUTOINCREMENT, item TEXT, kind TEXT,  -- done | skip | link
       link TEXT, reason TEXT, note TEXT, at INTEGER)
kv(k TEXT PRIMARY KEY, v TEXT, updated INTEGER)  -- growth JSON lives at k = "growth"
```

App token:
- `GET /v1/queues`: `{"day": "2026-10-13", "platforms": {"reddit": {"post": Queue, "comment": Queue}, "hn": {...}}}`. Queue = `{"open": [Item], "done_today": 3, "skipped_today": 1, "target": 5}`. Open items oldest first.
- `POST /v1/items/:id/done`: `{"link": "https://..."}` or `{}`. Sets `done`, writes an event.
- `POST /v1/items/:id/skip`: `{"reason": "bad" | "later", "note": "..."}`. Sets `skipped`, writes an event.
- `POST /v1/items/:id/link`: `{"link": "..."}` to add or fix a link on a done item.
- `GET /v1/items?status=done&limit=50`: history, newest first.
- `GET /v1/growth`: the growth JSON as the engine last put it.

Engine token (`ENGINE_TOKEN`, new secret; the drafter keeps `DRAFTER_TOKEN`):
- `PUT /v1/items`: `{"items": [Item]}` upsert by id. The engine may change any field; the worker never resurrects an item the app already marked done/skipped (it keeps status, link, skip fields from the app when they are newer).
- `GET /v1/events?after=<seq>`: `{"events": [...], "last": <seq>}`.
- `PUT /v1/growth`: any JSON object, stored as is.
- `GET /v1/items?status=open` and `?day=` for reconciliation.
- When the drafter posts drafts for a share, the worker also upserts one `reddit/post` item per draft (`id = "photo-<share>-<n>"`, source photo, photos = share photos).

Growth JSON (engine-owned, the app renders what is there):

```json
{"updated": 1791900000,
 "karma": {"hn": [["2026-10-01", 99], ...], "reddit": [["2026-10-01", 117], ...]},
 "done":  {"hn": {"post": [["2026-10-13", 1]], "comment": [...]}, "reddit": {...}},
 "split": {"hn": {"own": 1, "last": 10, "need": 9}, "reddit": {"own": 0, "last": 10, "need": 0}},
 "best":  [{"platform": "reddit", "title": "...", "link": "...", "score": 22, "comments": 4}],
 "streak_days": 3}
```

## Engine (lives in the private Lurker repo, not here)

Runs on a Linux box (systemd user timers). Every minute: pull events, apply them, refill debounced gaps. Hourly: sweep, find missing links, refresh growth. Daily at the start of the day: fill each post queue with 5.
Material for post ideas: your notes (a local checkout of a private wiki, recent changes first), recent commits, links worth sharing from HN/lobste.rs; the 90/10 rule holds back ideas about your own work until 9 of the last 10 items on that site were about others'. Personal, family and employer details never go in a draft.

## chrome-fetch (own repo, public)

`GET /fetch?url=<url-encoded>` with `Authorization: Bearer <token>`, bound to one interface (e.g. a tailnet IP). Allowed hosts from config (default `www.reddit.com`, `old.reddit.com`). Opens a **new** tab in an already running Chrome over CDP (port from config), waits for load, returns `{"status": <http>, "body": "<document.body.innerText>"}`, and **closes the tab in a finally block**, even on timeout. One fetch at a time, at least N seconds apart (config, default 3). On start and every 10 minutes it closes any tab it opened that is still around (tracked by target id). No other tabs are touched.

## iOS app

- Two tabs: **Reddit** and **HN**. Each tab is a list with two sections: **Post queue** and **Comment queue**, each showing `done_today / target` in its header.
- Item card: title, target (r/sub), why, the draft text, source label. Buttons: **Open** (thread or submit page, in Safari), **Copy** (draft), **Done**, **Skip**.
- **Done** sheet: optional link field ("Leave it empty and Lurker will find it"), Save.
- **Skip** sheet: two choices, "It's bad" and "Not now", optional note, Skip.
- Pull to refresh; refresh every 60 s while the app is open and right after any action.
- A **profile button** (top right) opens the growth dashboard: karma lines per platform (Swift Charts), done per day, the 90/10 split per site, best recent posts, streak.
- Photo shares stay: the share extension is unchanged; drafted photos show up in the Reddit post queue with thumbnails.
- Personal builds carry server and token at build time (README); Settings only overrides.
