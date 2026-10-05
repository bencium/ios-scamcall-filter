#!/bin/sh
# Apple's lookup server code plus our patches, as an editable checkout in server/upstream (git-ignored).
#
#   server/dev.sh setup    clone Apple's code at the commit the Dockerfile pins, then apply each
#                          file in server/patches as one commit on the branch local-patches
#   server/dev.sh save     rewrite server/patches from the commits on local-patches, one file each
#   server/dev.sh check    confirm the patch files apply cleanly to the pinned code, and match
#                          local-patches if server/upstream exists (scripts/deploy.sh runs this)
#
# To change the server: setup, then edit and commit on local-patches in server/upstream, then save,
# then commit the patch files here. Build it with:
#   cd server/upstream && swift build -c release --product PIRService
set -eu
cd "$(dirname "$0")"
UPSTREAM=upstream
BRANCH=local-patches
REPO=https://github.com/apple/live-caller-id-lookup-example.git
PIN=$(sed -n 's/^ARG PIR_REF=//p' Dockerfile)   # the Dockerfile is the one place the version is pinned

setup() {
  [ ! -e "$UPSTREAM" ] || { echo "server/upstream already exists. Delete it to start again."; exit 1; }
  git clone --quiet "$REPO" "$UPSTREAM"
  git -C "$UPSTREAM" checkout --quiet -b "$BRANCH" "$PIN"
  for patch in patches/*.patch; do
    git -C "$UPSTREAM" apply "../$patch"
    git -C "$UPSTREAM" add -A
    git -C "$UPSTREAM" commit --quiet -m "$(basename "$patch" .patch | sed 's/^[0-9]*-//' | tr '-' ' ')"
  done
  echo "Ready: server/upstream on branch $BRANCH, with $(ls patches/*.patch | wc -l | tr -d ' ') patches applied."
}

save() {
  [ "$(git -C "$UPSTREAM" branch --show-current)" = "$BRANCH" ] \
    || { echo "server/upstream is not on $BRANCH. Commit your changes there first."; exit 1; }
  [ -z "$(git -C "$UPSTREAM" status --porcelain)" ] \
    || { echo "server/upstream has uncommitted changes. Commit them on $BRANCH first."; exit 1; }
  rm -f patches/*.patch
  number=0
  for commit in $(git -C "$UPSTREAM" rev-list --reverse "$PIN..$BRANCH"); do
    number=$((number + 1))
    # Files are numbered here, because the Dockerfile applies them in file-name order.
    name=$(git -C "$UPSTREAM" log -1 --format=%s "$commit" | sed 's/^[0-9]* *//' | tr -cs 'A-Za-z0-9' '-' | sed 's/-*$//')
    git -C "$UPSTREAM" diff-tree -p "$commit^" "$commit" > "$(printf 'patches/%04d-%s.patch' "$number" "$name")"
  done
  echo "Wrote $number patch files to server/patches. Review them with git diff, then commit."
}

check() {
  work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
  if [ -d "$UPSTREAM/.git" ]; then
    git clone --quiet --shared --no-checkout "$UPSTREAM" "$work/src"
  else
    git clone --quiet --no-checkout "$REPO" "$work/src"
  fi
  git -C "$work/src" checkout --quiet "$PIN"
  # Same command as the Dockerfile, so a pass here means the Fly build will apply them too.
  git -C "$work/src" apply "$PWD"/patches/*.patch \
    || { echo "server/patches no longer apply to Apple's code at $PIN. Fix them in server/upstream, then save."; exit 1; }
  [ -d "$UPSTREAM/.git" ] || { echo "Patches apply cleanly."; return; }
  [ -z "$(git -C "$UPSTREAM" status --porcelain)" ] \
    || { echo "server/upstream has uncommitted changes. Commit them on $BRANCH and save, or discard them."; exit 1; }
  git -C "$work/src" add -A
  [ "$(git -C "$work/src" write-tree)" = "$(git -C "$UPSTREAM" rev-parse "$BRANCH^{tree}")" ] \
    || { echo "server/upstream ($BRANCH) differs from server/patches. Run server/dev.sh save, then commit the patches."; exit 1; }
  echo "Patches apply cleanly and match server/upstream."
}

case "${1:-}" in
  setup) setup ;;
  save) save ;;
  check) check ;;
  *) echo "usage: server/dev.sh setup | save | check"; exit 2 ;;
esac
