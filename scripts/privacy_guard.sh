#!/bin/sh
# Stops personal data from reaching the public repository.
#
#   scripts/privacy_guard.sh --install    install as this clone's pre-commit and pre-push hook
#
# After installing, every commit and push is checked, and blocked if it adds:
#   - any value from .env: team ID, tokens, passwords, your server address, your Fly app name
#   - any pattern in private/guard-patterns.txt, one extended regular expression per line,
#     such as your computer's name, device IDs or phone numbers. That file is git-ignored,
#     so your patterns stay private.
#   - files that must never be committed: .env files, anything in private/, call-history
#     copies, signing profiles, generated secrets, your server/fly.toml and Lookup/Info.plist
# The guard never prints the value it found. Hooks live in .git/hooks and are never pushed.
set -eu
cd "$(git rev-parse --show-toplevel)"
FORBIDDEN='(^|/)\.env|^private/|\.storedata|\.mobileprovision$|^Shared/LookupSecrets\.swift$|^server/fly\.toml$|^Lookup/Info\.plist$'
ZERO=0000000000000000000000000000000000000000
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

if [ "${1:-}" = "--install" ]; then
  for hook in pre-commit pre-push; do
    printf '#!/bin/sh\nexec scripts/privacy_guard.sh --%s "$@"\n' "$hook" > ".git/hooks/$hook"
    chmod +x ".git/hooks/$hook"
  done
  echo "Privacy guard installed for commits and pushes."
  exit 0
fi

# Secrets: every .env value of six characters or more, matched as plain text.
[ -f .env ] && sed -n 's/^[A-Za-z_][A-Za-z0-9_]*=//p' .env | awk 'length($0) >= 6' > "$WORK/secrets" || : > "$WORK/secrets"
# Personal patterns, without comments and blank lines.
grep -v -E '^[[:space:]]*(#|$)' private/guard-patterns.txt 2>/dev/null > "$WORK/patterns" || : > "$WORK/patterns"

# check_change FILE: reads the file's diff on stdin and records any problem. It runs at the end
# of a pipe (a sub-shell), so problems are recorded as a marker file, not a variable.
check_change() {
  if echo "$1" | grep -q -E "$FORBIDDEN"; then
    echo "privacy guard: $1 must never be committed."; touch "$WORK/blocked"; return
  fi
  grep '^+' | grep -v '^+++' > "$WORK/added" || true
  if [ -s "$WORK/secrets" ] && grep -q -F -f "$WORK/secrets" "$WORK/added"; then
    echo "privacy guard: $1 adds a value from .env."; touch "$WORK/blocked"
  fi
  if [ -s "$WORK/patterns" ] && grep -q -E -f "$WORK/patterns" "$WORK/added"; then
    echo "privacy guard: $1 adds something listed in private/guard-patterns.txt."; touch "$WORK/blocked"
  fi
}

case "${1:-}" in
  --pre-commit)
    for file in $(git diff --cached --name-only --diff-filter=ACMR); do
      git diff --cached -U0 -- "$file" | check_change "$file"
    done ;;
  --pre-push)
    while read -r _ local_sha _ remote_sha; do
      [ "$local_sha" = "$ZERO" ] && continue
      if [ "$remote_sha" = "$ZERO" ]; then range=$(git rev-list "$local_sha" --not --remotes)
      else range=$(git rev-list "$remote_sha..$local_sha"); fi
      for commit in $range; do
        for file in $(git diff-tree --no-commit-id --name-only -r --diff-filter=ACMR "$commit"); do
          git show --format= -U0 "$commit" -- "$file" | check_change "$file"
        done
      done
    done ;;
  *) echo "usage: scripts/privacy_guard.sh --install"; exit 2 ;;
esac

if [ -f "$WORK/blocked" ]; then
  echo "Blocked to keep private data out of the public repository. Remove it and try again."
  exit 1
fi
