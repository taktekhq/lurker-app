#!/bin/sh
# Deploy the worker over the Cloudflare REST API. No wrangler login needed.
#
# Required environment:
#   CF_API_TOKEN   Cloudflare API token with Workers Scripts Edit, D1 Edit
#                  and Workers KV/R2 bindings read permission on the account.
#   CF_ACCOUNT_ID  Cloudflare account id.
#
# Usage:
#   CF_API_TOKEN=... CF_ACCOUNT_ID=... ./deploy.sh [worker-name] [r2-bucket] [d1-database-id]
#
# Defaults: worker-name=lurker-inbox, r2-bucket=lurker-inbox, d1-database-id
# read from D1_DATABASE_ID in the environment if not given as an argument.
#
# This script only uploads the script and sets its bindings. Create the R2
# bucket, create the D1 database, apply schema.sql, set the APP_TOKEN and
# DRAFTER_TOKEN secrets, and enable the workers.dev subdomain separately
# (one-time setup, see README.md).

set -eu

: "${CF_API_TOKEN:?set CF_API_TOKEN}"
: "${CF_ACCOUNT_ID:?set CF_ACCOUNT_ID}"

WORKER_NAME="${1:-${WORKER_NAME:-lurker-inbox}}"
R2_BUCKET="${2:-${R2_BUCKET:-lurker-inbox}}"
D1_DATABASE_ID="${3:-${D1_DATABASE_ID:?set D1_DATABASE_ID or pass it as the third argument}}"

cd "$(dirname "$0")"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

cat > "$tmpdir/meta.json" <<JSON
{
  "main_module": "worker.js",
  "compatibility_date": "2024-09-23",
  "bindings": [
    { "type": "r2_bucket", "name": "PHOTOS", "bucket_name": "$R2_BUCKET" },
    { "type": "d1", "name": "DB", "id": "$D1_DATABASE_ID" }
  ]
}
JSON

echo "Deploying $WORKER_NAME to account $CF_ACCOUNT_ID ..."

curl -sS -X PUT \
  -H "Authorization: Bearer $CF_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/workers/scripts/$WORKER_NAME" \
  -F "metadata=@$tmpdir/meta.json;type=application/json" \
  -F "worker.js=@worker.js;type=application/javascript+module"

echo
echo "Done. Secrets (APP_TOKEN, DRAFTER_TOKEN) and the workers.dev subdomain are set separately."
