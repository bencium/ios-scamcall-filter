#!/bin/sh
# Copies the iPhone's call history into private/backup-copy from a fresh encrypted backup, over
# the cable. The Mac's synced history can be days behind; this copy is as new as the backup.
#
#   scripts/call_history.sh       back up the phone, then extract the call history
#   python3 scripts/report.py     reads private/backup-copy first
#
# One-time setup:
#   1. Finder > your iPhone > General: choose "Back up all the data on your iPhone to this Mac",
#      tick "Encrypt local backup" and set a password. iOS keeps call history only in encrypted
#      backups. The first backup copies everything; later ones copy only the changes.
#   2. Save that password in the Keychain. This prompts for it, so it never shows on screen:
#        security add-generic-password -a "$USER" -s 084x-blocker-backup -w
#   3. System Settings > Privacy & Security > Full Disk Access: turn on your terminal app, then
#      quit and reopen it. Without this, macOS hides the backup folder from the terminal.
# Uses Apple's own backup tool. The password is passed to it as an argument, so other programs
# on this Mac could see it in the process list for the few seconds the extract runs.
set -eu
cd "$(dirname "$0")/.."
TOOL=/System/Library/PrivateFrameworks/MobileDevice.framework/Versions/A/AppleMobileDeviceHelper.app/Contents/Resources/AppleMobileBackup
KEYCHAIN_ITEM=084x-blocker-backup
HISTORY=Library/CallHistoryDB/CallHistory.storedata
COPY=private/backup-copy
LOG=/tmp/084x-call-history.log

BACKUPS="$HOME/Library/Application Support/MobileSync"
if [ -e "$BACKUPS" ] && ! ls "$BACKUPS" > /dev/null 2>&1; then
  echo "This terminal can't read the phone backups. Give it Full Disk Access (setup step 3)."; exit 1
fi
password=$(security find-generic-password -a "$USER" -s "$KEYCHAIN_ITEM" -w 2>/dev/null) \
  || { echo "No backup password in the Keychain. Run setup step 2 (see the top of this script)."; exit 1; }
device=$(scripts/phone_device.sh)

echo "Backing up the phone. Keep it connected and unlocked..."
"$TOOL" --backup --target "$device" < /dev/null > "$LOG" 2>&1 \
  || { echo "Backup failed. See $LOG."; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
cd "$work"
"$TOOL" --extract "$HISTORY" --domain HomeDomain --target "$device" --password "$password" \
  < /dev/null >> "$LOG" 2>&1 || { echo "Could not extract the call history. See $LOG."; exit 1; }
# The database's two side files exist only when the phone had unsaved changes at backup time.
for side in -wal -shm; do
  "$TOOL" --extract "$HISTORY$side" --domain HomeDomain --target "$device" --password "$password" \
    < /dev/null >> "$LOG" 2>&1 || true
done
cd - > /dev/null

extracted=$(find "$work" -name CallHistory.storedata -type f | head -1)
[ -n "$extracted" ] || { echo "The backup tool reported success but wrote no file. See $LOG."; exit 1; }
rm -rf "$COPY"; mkdir -p "$COPY"
mv "$(dirname "$extracted")"/CallHistory.storedata* "$COPY"/
echo "Call history copied to $COPY. Run: python3 scripts/report.py"
