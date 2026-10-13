# Spec

Share photos from your iPhone, get Reddit post drafts back. You post them yourself.

```
iPhone share sheet ──POST──> Cloudflare Worker (R2 photos, D1 rows) <──poll── drafter (any Linux box, claude -p)
iPhone app <──GET drafts──┘
```

Nothing here is specific to one person. The server URL, tokens, subreddit list and voice are config.

## Worker (`worker/`)

Plain JS module, no build step. Bindings: R2 `PHOTOS`, D1 `DB`, secret text `APP_TOKEN` and `DRAFTER_TOKEN`.
Deploy script uses the Cloudflare REST API with `CF_API_TOKEN` and `CF_ACCOUNT_ID` from the environment (no wrangler login needed).

### Tables

```sql
shares(id TEXT PRIMARY KEY, note TEXT, photos TEXT,  -- JSON array of R2 keys
       status TEXT,  -- new | drafting | drafted | failed | posted | skipped
       drafts TEXT,  -- JSON array of Draft
       error TEXT, created INTEGER, updated INTEGER)
rules(sub TEXT PRIMARY KEY, rules TEXT, updated INTEGER)  -- JSON array of strings
```

### Routes

Every route but `/health` needs `Authorization: Bearer <token>`. Wrong or missing token: 401.

App token:
- `POST /v1/shares`: multipart. `note` text (optional, max 2000 chars), `photo` 1 to 10 files, `image/jpeg`, max 5 MB each. Returns 201 `{"id": "..."}`.
- `GET /v1/shares`: newest first, max 100. Drops `posted`/`skipped` rows older than 30 days. Returns `{"shares": [Share]}`.
- `POST /v1/shares/:id/status`: body `{"status": "posted" | "skipped" | "new"}`. `new` asks for fresh drafts.
- `DELETE /v1/shares/:id`: deletes the row and its photos.

Drafter token:
- `POST /v1/claim`: takes the oldest `new` share (or a `drafting` one untouched for 15 min), sets `drafting`, returns the Share. 204 when there is none.
- `POST /v1/shares/:id/drafts`: body `{"drafts": [Draft]}` sets `drafted`; body `{"error": "..."}` sets `failed`.
- `PUT /v1/rules`: body `{"<sub>": ["rule", ...], ...}`, upserts.
- `GET /v1/rules`: returns the same shape.

Either token:
- `GET /v1/photos/:key`: the JPEG.

Share: `{"id", "note", "status", "created", "updated", "photos": ["<key>", ...], "drafts": [Draft], "error"}`.
Draft: `{"sub": "Ducati", "title": "...", "body": "", "why": "one line: why this sub", "rules_checked": true, "rule_notes": "no flair needed"}`.

## Drafter (`drafter/`)

Go, one binary. `drafter run` polls every 30 s; `drafter once` handles one share and exits. Config file (path from `-config`, default `~/.config/lurker-drafter/config.json`):

```json
{"inbox_url": "https://...", "token_env": "DRAFTER_TOKEN",
 "claude": ["claude", "-p", "--model", "sonnet"],
 "voice_file": "~/.config/lurker-drafter/voice.md",
 "subs": [{"name": "Ducati", "for": "his own bike, rides, parts"}]}
```

For each claimed share: download photos to a temp dir, fetch `/v1/rules`, run claude with the image paths (it reads them with its Read tool; no MCP servers: `--strict-mcp-config`), ask for JSON with 1 to 3 drafts.

Gates before posting drafts back, any failure drops that draft (all dropped means `failed` with the reasons):
- `sub` must be in the config list.
- `rules_checked` is set by the drafter, not the model: true only when the sub has rules in `/v1/rules`.
- No em dash or en dash in title or body.
- Title under 300 chars (Reddit's limit).
- The prompt forbids facts that are neither visible in the photo nor in the note (places, dates, names, numbers). The model must list, per draft, which facts came from the note and which from the photo.

## iOS app (`ios/`)

SwiftUI, iOS 18, xcodegen `project.yml`. Bundle `io.taktek.lurker`, no app group. Server URL and token live in a keychain group both targets share (`<team prefix>io.taktek.lurker.shared`), set in Settings.

- **Share extension**: accepts 1 to 10 images. Thumbnails, a note field, Send. Resizes to 1600 px on the long edge, JPEG 0.8 (re-encoding drops EXIF, GPS included). Shows sent or the error.
- **App**: list of shares, newest first, pull to refresh, refreshes every 5 s while any share is `new` or `drafting`. Each share shows its photos, note, status and draft cards: sub, title, body, why, rule notes. Buttons: Copy title, Copy body, Posted, Skip, Redo. Draft only: it never opens Reddit or posts.
- **Settings**: server URL, token, a Test button that calls `GET /v1/shares`.
