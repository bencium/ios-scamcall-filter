#!/bin/sh
# Shows the blocker's state on the iPhone, read over the cable: which switches are on, the last
# parts check and the last server refresh.
#
#   scripts/phone_status.sh
#
# Opens the app on the phone (it must be unlocked), which makes it re-read the iOS switches and
# rewrite Documents/status.json, then copies that file to this Mac and prints it. If the app
# can't be opened, it prints the last file the app wrote; its "written" time says how old it is.
set -eu
cd "$(dirname "$0")/.."
APP_ID=uk.co.bencium.ScamBlocker
device=$(scripts/phone_device.sh)
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

fetch() {
  xcrun devicectl device copy from --device "$device" --domain-type appDataContainer \
    --domain-identifier "$APP_ID" --source Documents/status.json --destination "$work/status.json" \
    > "$work/copy.log" 2>&1
}
written() { plutil -extract written raw -o - "$work/status.json" 2>/dev/null || true; }

opened=$(date -u +%Y-%m-%dT%H:%M:%SZ)
if xcrun devicectl device process launch --device "$device" --terminate-existing "$APP_ID" > "$work/launch.log" 2>&1; then
  # The app saves the file once it has read every switch, usually within a few seconds.
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    sleep 1
    if fetch && ! [ "$(written)" \< "$opened" ]; then cat "$work/status.json"; echo; exit 0; fi
  done
  echo "The app opened but didn't save a new status within 10 seconds. Showing the last one." >&2
else
  echo "Could not open the app (is the phone unlocked?). Showing the last status it saved." >&2
fi
if ! fetch; then
  echo "Could not copy the status file: $(grep -m1 'ERROR' "$work/copy.log" || tail -1 "$work/copy.log")" >&2
  echo "Unlock the phone and run again. If it still fails, open 084x Blocker once: the file appears on first launch." >&2
  exit 1
fi
cat "$work/status.json"; echo
