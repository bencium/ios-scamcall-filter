#!/bin/sh
# Deploys the lookup server to Fly.io, but only when the deploy will match a commit on main:
#   - you are on main, and nothing is uncommitted (ignored files such as .env don't count)
#   - the server patches still apply to Apple's pinned code, and match server/upstream if it exists
#   - server/fly.toml names the same Fly app as FLY_APP in .env
#
#   scripts/deploy.sh             deploy, building on Fly's machines (no Docker needed here)
#   scripts/deploy.sh --detach    extra arguments go to fly deploy
#
# A Claude Code hook (.claude/hooks/require_deploy_script.py) blocks running fly deploy directly.
set -eu
cd "$(dirname "$0")/.."
refuse() { echo "Deploy refused: $1"; exit 1; }

[ "$(git branch --show-current)" = main ] || refuse "switch to main first. Deploys come only from main."
[ -z "$(git status --porcelain)" ] \
  || refuse "commit or discard these changes first, so the server matches a commit:
$(git status --short)"

app=$(sed -n 's/^app *= *"\([^"]*\)".*/\1/p' server/fly.toml 2>/dev/null || true)
fly_app=$(sed -n 's/^FLY_APP=//p' .env 2>/dev/null | tr -d '"'"'" || true)
[ -n "$app" ] || refuse "server/fly.toml is missing or has no app name. Copy server/fly.example.toml and set it."
[ "$app" = "$fly_app" ] || refuse "server/fly.toml and FLY_APP in .env name different Fly apps."
server/dev.sh check || refuse "the server patches are not ready (see above)."

echo "Deploying commit $(git rev-parse --short HEAD)..."
cd server
fly deploy --remote-only "$@"
