#!/bin/sh
# Prints the identifier of the iPhone the scripts talk to: DEVICE_ID from .env, else the first
# paired iPhone. Used by resign.sh, phone_status.sh and call_history.sh.
set -eu
cd "$(dirname "$0")/.."
device=${DEVICE_ID:-$(sed -n 's/^DEVICE_ID=//p' .env 2>/dev/null || true)}
[ -n "$device" ] || device=$(xcrun devicectl list devices --json-output /dev/stdout 2>/dev/null | python3 -c '
import json, sys
text = sys.stdin.read(); data = json.loads(text[text.index("{"):])
for d in data["result"]["devices"]:
    props, hw = d.get("connectionProperties", {}), d.get("hardwareProperties", {})
    if hw.get("deviceType") == "iPhone" and hw.get("reality") == "physical" and props.get("pairingState") == "paired":
        print(hw["udid"]); break')
[ -n "$device" ] || { echo "No paired iPhone found. Plug the phone in, unlock it, and run again." >&2; exit 1; }
echo "$device"
