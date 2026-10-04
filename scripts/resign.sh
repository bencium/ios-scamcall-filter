#!/bin/sh
# Re-sign the app before Apple's 7-day free-account profiles expire, and reinstall it.
#
#   scripts/resign.sh             re-sign only if a profile expires within 48 hours
#   FORCE=1 scripts/resign.sh     re-sign now
#
# Needs the iPhone paired with this Mac (cable, or same Wi-Fi once paired) and .env with
# DEVELOPMENT_TEAM. DEVICE_ID in .env picks the phone; otherwise the first paired iPhone.
# Builds whatever scripts/create_project.py last generated (normal or fallback mode).
# Expiring profiles are moved to a backup folder, never deleted, so Xcode issues fresh ones.
set -eu
cd "$(dirname "$0")/.."
APP=build/Build/Products/Release-iphoneos/ScamBlocker.app
PENDING=build/.install-pending   # a fresh build that hasn't reached the phone yet
PROFILES="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
BACKUP="$HOME/Library/Developer/Xcode/UserData/expired-profiles-backup"
set -a; . ./.env; set +a

profile() { security cms -D -i "$1/embedded.mobileprovision" 2>/dev/null | plutil -extract "$2" raw -o - - 2>/dev/null || true; }
bundles() { ls -d "$APP" "$APP"/PlugIns/*.appex "$APP"/Extensions/*.appex 2>/dev/null; }
earliest() { for b in $(bundles); do profile "$b" ExpirationDate; done | sort | head -1; }

soon=$(date -u -v+48H +%Y-%m-%dT%H:%M:%SZ)
due=""
for b in $(bundles); do
  e=$(profile "$b" ExpirationDate)
  if [ -z "$e" ] || [ "$e" \< "$soon" ]; then due="$due $b"; fi
done
if [ ! -d "$APP" ]; then due="no previous build"; fi
if [ -f "$PENDING" ] && [ -z "$due" ] && [ "${FORCE:-0}" != 1 ]; then
  echo "A re-signed build is waiting to be installed."
elif [ -z "$due" ] && [ "${FORCE:-0}" != 1 ]; then
  echo "Nothing to do: the earliest profile expires $(earliest)."
  exit 0
fi

device=${DEVICE_ID:-$(xcrun devicectl list devices --json-output /dev/stdout 2>/dev/null | python3 -c '
import json, sys
text = sys.stdin.read(); data = json.loads(text[text.index("{"):])
for d in data["result"]["devices"]:
    props, hw = d.get("connectionProperties", {}), d.get("hardwareProperties", {})
    if hw.get("deviceType") == "iPhone" and hw.get("reality") == "physical" and props.get("pairingState") == "paired":
        print(hw["udid"]); break')}
[ -n "$device" ] || { echo "No paired iPhone found. Plug the phone in, unlock it, and run again."; exit 1; }

install_build() {
  xcrun devicectl device install app --device "$device" "$APP" > /tmp/scamblocker-install.log 2>&1 \
    || { echo "Install failed; is the phone unlocked? See /tmp/scamblocker-install.log. Run again to retry."; exit 1; }
  rm -f "$PENDING"
  echo "Installed. Next re-sign due by $(earliest)."
}
if [ -f "$PENDING" ] && [ -z "$due" ] && [ "${FORCE:-0}" != 1 ]; then install_build; exit 0; fi

mkdir -p "$BACKUP"
for b in $(bundles); do
  u=$(profile "$b" UUID)
  [ -n "$u" ] && [ -f "$PROFILES/$u.mobileprovision" ] && mv "$PROFILES/$u.mobileprovision" "$BACKUP/"
done
echo "Building with fresh profiles..."
xcodebuild -project ScamBlocker.xcodeproj -scheme ScamBlocker -configuration Release \
  -destination "generic/platform=iOS" -derivedDataPath build -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" build > /tmp/scamblocker-resign.log 2>&1 \
  || { echo "Build failed; see /tmp/scamblocker-resign.log"; exit 1; }
codesign --verify --deep --strict "$APP"
fresh=$(date -u -v+6d +%Y-%m-%dT%H:%M:%SZ)
for b in $(bundles); do
  e=$(profile "$b" ExpirationDate)
  [ "$e" \> "$fresh" ] || { echo "$(basename "$b") still expires $e; Xcode did not renew it."; exit 1; }
done
touch "$PENDING"
install_build
