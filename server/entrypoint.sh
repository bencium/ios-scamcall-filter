#!/bin/sh
# Writes the service config from secrets, then runs PIRService on the volume data.
# LOOKUP_TOKEN: the bearer token the phone sends (same base64 string as in the app's .env).
# SHARD_COUNT: number of block shards uploaded to /data (must match the build).
# Until a database has been uploaded and marked complete with /data/READY, the server waits
# instead of crash-looping, so the first deploy can happen before the upload.
# /data/state keeps the token-signing key and the phones' uploaded keys across restarts
# (patches/0002), so the machine can stop when idle without breaking the phone's lookups.
# /data/metrics holds the lookup log and the phone summary behind /dashboard (patches/0003);
# the dashboard stays off unless the DASHBOARD_PASSWORD secret is set.
set -eu
: "${LOOKUP_TOKEN:?set with: fly secrets set LOOKUP_TOKEN=...}"
: "${SHARD_COUNT:?set in fly.toml [env]}"
until [ -f /data/READY ]; do
  echo "waiting for database upload: /data/READY not found (see README, Server lookup)"
  sleep 30
done
cat > /data/service-config.json <<CONFIG
{
  "tokens": ["$LOOKUP_TOKEN"],
  "usecases": [
    { "fileStem": "/data/block", "shardCount": $SHARD_COUNT, "name": "uk.co.bencium.ScamBlocker.Lookup.block" },
    { "fileStem": "/data/identity", "shardCount": 1, "name": "uk.co.bencium.ScamBlocker.Lookup.identity" }
  ]
}
CONFIG
exec /usr/local/bin/PIRService --hostname 0.0.0.0 --port 8080 --state-directory /data/state \
  --metrics-directory /data/metrics --dashboard-page /usr/local/share/scamblocker/dashboard.html \
  /data/service-config.json
