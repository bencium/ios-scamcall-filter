#!/bin/sh
# Upload a built lookup database to the Fly volume and start (or restart) the server on it.
#
#   scripts/lookup/upload_db.sh DBDIR [APP]        (APP defaults to FLY_APP in .env)
#
# The database is ~11 GB for 60M numbers and barely compresses, and flyctl's tunnel runs at
# roughly 2 MB/s, so this takes over an hour. It goes up in 16 independent tar parts; each is
# uploaded, unpacked on the volume and deleted before the next, so the volume only needs room
# for the database plus one part. Finished parts are marked on the volume, so rerunning after a
# dropped connection resumes where it stopped (FRESH=1 starts over). Files land in
# /data/incoming and replace the live set only once every part has arrived.
# Avoid other `fly ssh` sessions to the app while this runs; they can drop the transfer.
set -eu
DB=$1
APP=${2:-$(sed -n 's/^FLY_APP=//p' "$(dirname "$0")/../../.env" 2>/dev/null)}
[ -n "$APP" ] || { echo "Give the Fly app name, or set FLY_APP in .env"; exit 1; }
PARTS=16
WORK=$(mktemp -d /tmp/lookup-upload.XXXXXX)
trap 'rm -rf "$WORK"' EXIT
remote() { fly ssh console -q -a "$APP" -C "sh -c '$1'"; }
retry() { n=1; until "$@"; do [ $n -ge 4 ] && return 1; echo "  retry $n: $*" | cut -c1-80; n=$((n + 1)); sleep 10; done; }

if [ "${FRESH:-0}" = 1 ]; then remote "rm -rf /data/incoming"; fi
retry remote "mkdir -p /data/incoming && rm -f /data/incoming/part.tar && df -h /data | tail -1"
done_parts=$(remote "ls -a /data/incoming | grep -E \"^\\.part-[0-9]+-done\$\" || true" | tr -d '\r')
part=0
while [ "$part" -lt "$PARTS" ]; do
  if echo "$done_parts" | grep -qx ".part-$part-done"; then
    echo "part $((part + 1))/$PARTS: already on the volume"
    part=$((part + 1)); continue
  fi
  (cd "$DB" && ls | grep -E '^(block|identity)-[0-9]+\.' | awk -v p="$part" -v n="$PARTS" -F'[-.]' '$2 % n == p' > "$WORK/list")
  COPYFILE_DISABLE=1 tar --no-xattrs --no-mac-metadata -cf "$WORK/part.tar" -C "$DB" -T "$WORK/list"
  echo "part $((part + 1))/$PARTS: $(wc -l < "$WORK/list" | tr -d ' ') files, $(du -h "$WORK/part.tar" | cut -f1), started $(date +%H:%M)"
  retry fly ssh sftp put -a "$APP" "$WORK/part.tar" /data/incoming/part.tar
  retry remote "tar -xf /data/incoming/part.tar -C /data/incoming && rm /data/incoming/part.tar && touch /data/incoming/.part-$part-done"
  rm "$WORK/part.tar"
  part=$((part + 1))
done
expected=$(cd "$DB" && ls | grep -cE '^(block|identity)-[0-9]+\.')
remote "n=\$(ls /data/incoming | grep -cE \"^(block|identity)-\"); echo \"files on volume: \$n of $expected\"; [ \$n -eq $expected ]"
remote "rm -f /data/block-* /data/identity-* && mv /data/incoming/block-* /data/incoming/identity-* /data/ && rm -rf /data/incoming && touch /data/READY"
fly apps restart "$APP"
echo "uploaded; server restarting on the new database"
