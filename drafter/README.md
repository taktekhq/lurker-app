# drafter

Go binary that polls the lurker-app worker for shared photos and turns each
one into Reddit post drafts using the `claude` CLI. Routes it talks to are
documented in [SPEC.md](../SPEC.md) at the repo root. No third-party
dependencies.

## Build and test

```sh
cd drafter
go build ./...
go test ./...
```

Tests use `httptest` for a fake worker and an injected fake for the claude
call, so nothing talks to a real Cloudflare worker or runs `claude`.

## Run

```sh
drafter run              # polls every 30s, forever
drafter once              # handles at most one share and exits
drafter run -config /path/to/config.json
```

Default config path: `~/.config/lurker-drafter/config.json`.

## Config file

```json
{
  "inbox_url": "https://your-worker.your-subdomain.workers.dev",
  "token_env": "DRAFTER_TOKEN",
  "claude": ["claude", "-p", "--model", "sonnet"],
  "voice_file": "~/.config/lurker-drafter/voice.md",
  "subs": [
    {"name": "Ducati", "for": "his own bike, rides, parts"}
  ]
}
```

- `inbox_url`: the worker's URL (no trailing slash needed).
- `token_env`: environment variable holding the drafter token. Defaults to
  `DRAFTER_TOKEN`. Set it in the environment the service runs under, never
  in this file.
- `claude`: the base command used to run claude. If the binary is not on
  the PATH the process runs under, give its absolute path here, e.g.
  `["/home/you/.local/bin/claude", "-p", "--model", "sonnet"]`.
- `voice_file`: a plain text file describing how drafts should sound. `~`
  expands to the home directory.
- `subs`: the only subreddits the drafter is allowed to draft for. Each
  needs a `name` and a one-line `for` description used in the prompt. A
  draft for any other subreddit is dropped.

## Rules cache

`PUT /v1/rules` and `GET /v1/rules` on the worker hold a small cache of
each subreddit's posting rules (fetched by whatever keeps it fresh; this
binary does not scrape Reddit itself). The drafter reads this cache before
every draft and only sets `rules_checked: true` on a draft when its sub
has an entry there, regardless of what the model claims.

## Deploying as a systemd user service

Example `~/.config/systemd/user/lurker-drafter.service`:

```ini
[Unit]
Description=lurker-app drafter

[Service]
EnvironmentFile=%h/.config/lurker-drafter/env
ExecStart=%h/go/bin/drafter run
Restart=on-failure

[Install]
WantedBy=default.target
```

`%h/.config/lurker-drafter/env` holds `DRAFTER_TOKEN=...` (mode 600, never
committed anywhere). Enable linger once so the service keeps running after
you log out (`loginctl enable-linger $(whoami)`), then:

```sh
systemctl --user daemon-reload
systemctl --user enable --now lurker-drafter.service
systemctl --user status lurker-drafter.service
```
