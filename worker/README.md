# worker

Cloudflare Worker that stores shared photos (R2), share/draft rows, and
post/comment queue items and events (D1). It is the API the iOS app, the
drafter and the engine all talk to. Routes are documented in
[SPEC.md](../SPEC.md) (photo shares) and [SPEC-v2.md](../SPEC-v2.md)
(queues, events, growth) at the repo root. Plain JS, no build step, no npm
dependencies.

## Run the tests

```sh
cd worker
node --test
```

Tests use small in-memory fakes for the R2 and D1 bindings (`test-helpers.js`),
so nothing talks to Cloudflare.

## One-time Cloudflare setup

You need a Cloudflare account and an API token (Workers Scripts Edit, D1
Edit, and read access to the R2 bucket's binding). Wrangler login is not
required; everything below goes through the REST API with curl.

Three bearer tokens guard the routes: `APP_TOKEN` (the iOS app),
`DRAFTER_TOKEN` (the photo-share drafter, SPEC.md), and `ENGINE_TOKEN` (the
queue-filling engine, SPEC-v2.md). Generate and set all three the same way;
keep each one out of logs and source control.

```sh
export CF_API_TOKEN=...      # your token
export CF_ACCOUNT_ID=...     # your account id
WORKER_NAME=lurker-inbox     # pick any name
R2_BUCKET=lurker-inbox       # an R2 bucket you already created
```

1. Create the R2 bucket if it does not exist yet (dashboard, or
   `POST /accounts/$CF_ACCOUNT_ID/r2/buckets` with `{"name":"'"$R2_BUCKET"'"}`).

2. Create the D1 database and apply the schema:

   ```sh
   curl -sS -X POST -H "Authorization: Bearer $CF_API_TOKEN" \
     "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/d1/database" \
     -H "content-type: application/json" \
     -d '{"name":"'"$WORKER_NAME"'"}'
   # note the "uuid" from the response as D1_DATABASE_ID

   curl -sS -X POST -H "Authorization: Bearer $CF_API_TOKEN" \
     "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/d1/database/$D1_DATABASE_ID/query" \
     -H "content-type: application/json" \
     --data-binary @- <<'JSON'
   {"sql": "CREATE TABLE IF NOT EXISTS shares (id TEXT PRIMARY KEY, note TEXT, photos TEXT NOT NULL, status TEXT NOT NULL, drafts TEXT, error TEXT, created INTEGER NOT NULL, updated INTEGER NOT NULL)"}
   JSON
   ```

   Or run each statement in `schema.sql` the same way; it is idempotent.
   `schema.sql` also has the `items`, `events` and `kv` tables SPEC-v2.md
   adds (post/comment queues); apply those the same way.

3. Deploy the worker:

   ```sh
   ./deploy.sh "$WORKER_NAME" "$R2_BUCKET" "$D1_DATABASE_ID"
   ```

4. Set the two secrets (generate your own random values, do not reuse an
   example):

   ```sh
   APP_TOKEN=$(openssl rand -hex 32)
   DRAFTER_TOKEN=$(openssl rand -hex 32)
   ENGINE_TOKEN=$(openssl rand -hex 32)

   for name in APP_TOKEN DRAFTER_TOKEN ENGINE_TOKEN; do
     value=$(eval echo \$$name)
     curl -sS -X PUT -H "Authorization: Bearer $CF_API_TOKEN" \
       -H "content-type: application/json" \
       "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/workers/scripts/$WORKER_NAME/secrets" \
       -d '{"name":"'"$name"'","text":"'"$value"'","type":"secret_text"}'
   done
   ```

   Store `APP_TOKEN` in the iOS app's Settings screen, `DRAFTER_TOKEN` in the
   drafter's environment, and `ENGINE_TOKEN` in the engine's environment.
   Never print or log any of them.

5. Enable the workers.dev subdomain so the worker is reachable without a
   custom domain:

   ```sh
   curl -sS -X POST -H "Authorization: Bearer $CF_API_TOKEN" \
     -H "content-type: application/json" \
     "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/workers/scripts/$WORKER_NAME/subdomain" \
     -d '{"enabled":true}'
   ```

   The worker is then at `https://$WORKER_NAME.<your-subdomain>.workers.dev`.

To redeploy after a code change, just run `./deploy.sh` again; it does not
touch secrets or the subdomain.
