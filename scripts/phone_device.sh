#!/bin/sh
# Prints the identifier of the iPhone the scripts talk to: DEVICE_ID from .env, else the one
# paired iPhone that is connected right now. Used by resign.sh, phone_status.sh and call_history.sh.
# Paired phones that aren't connected are skipped: picking one of those once sent every install to
# a phone that wasn't there. If several are connected, set DEVICE_ID in .env.
set -eu
cd "$(dirname "$0")/.."
device=${DEVICE_ID:-$(sed -n 's/^DEVICE_ID=//p' .env 2>/dev/null || true)}
[ -n "$device" ] && { echo "$device"; exit 0; }
xcrun devicectl list devices --json-output /dev/stdout 2>/dev/null | python3 -c '
import json, sys
text = sys.stdin.read(); data = json.loads(text[text.index("{"):])
connected = []
for d in data["result"]["devices"]:
    props, hw = d.get("connectionProperties", {}), d.get("hardwareProperties", {})
    if (hw.get("deviceType") == "iPhone" and hw.get("reality") == "physical"
            and props.get("pairingState") == "paired" and props.get("transportType")):
        connected.append((hw["udid"], d.get("deviceProperties", {}).get("name", "?")))
if len(connected) == 1:
    print(connected[0][0])
elif not connected:
    sys.exit("No connected iPhone. Plug the phone in, unlock it, and run again.")
else:
    sys.exit("Several iPhones are connected (" + ", ".join(name for _, name in connected)
             + "). Set DEVICE_ID in .env to the one to use.")'
