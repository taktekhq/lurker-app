# worker

Cloudflare Worker that stores shared photos (R2) and share/draft rows (D1),
and is the API both the iOS app and the drafter talk to. Routes are
documented in [SPEC.md](../SPEC.md) at the repo root. Plain JS, no build
step, no npm dependencies.

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

3. Deploy the worker:

   ```sh
   ./deploy.sh "$WORKER_NAME" "$R2_BUCKET" "$D1_DATABASE_ID"
   ```

4. Set the two secrets (generate your own random values, do not reuse an
   example):

   ```sh
   APP_TOKEN=$(openssl rand -hex 32)
   DRAFTER_TOKEN=$(openssl rand -hex 32)

   curl -sS -X PUT -H "Authorization: Bearer $CF_API_TOKEN" \
     -H "content-type: application/json" \
     "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/workers/scripts/$WORKER_NAME/secrets" \
     -d '{"name":"APP_TOKEN","text":"'"$APP_TOKEN"'","type":"secret_text"}'

   curl -sS -X PUT -H "Authorization: Bearer $CF_API_TOKEN" \
     -H "content-type: application/json" \
     "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/workers/scripts/$WORKER_NAME/secrets" \
     -d '{"name":"DRAFTER_TOKEN","text":"'"$DRAFTER_TOKEN"'","type":"secret_text"}'
   ```

   Store `APP_TOKEN` in the iOS app's Settings screen, and `DRAFTER_TOKEN` in
   the drafter's environment. Never print or log either one.

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
