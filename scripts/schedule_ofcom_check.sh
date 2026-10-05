#!/bin/sh
# Runs the Ofcom numbering check on this Mac on the 1st of every month at 09:00 (launchd).
# A run missed while the Mac sleeps happens when it wakes. A change or a failure shows a Mac
# notification; every run posts its result to the server, where the app shows it.
#
#   scripts/schedule_ofcom_check.sh --install    install or update the schedule
#   scripts/schedule_ofcom_check.sh --run-now    run the scheduled check once, now
#   scripts/schedule_ofcom_check.sh --remove     stop it
#
# Log: ~/Library/Logs/084x-ofcom-check.log
set -eu
cd "$(dirname "$0")/.."
LABEL=uk.co.bencium.084x.ofcom-check
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/084x-ofcom-check.log"
DOMAIN="gui/$(id -u)"

case "${1:-}" in
  --install)
    mkdir -p "$(dirname "$PLIST")" "$(dirname "$LOG")"
    cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$(command -v python3)</string>
    <string>$PWD/scripts/lookup/ofcom_changes.py</string>
    <string>--notify</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict><key>Day</key><integer>1</integer><key>Hour</key><integer>9</integer><key>Minute</key><integer>0</integer></dict>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
PLIST
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    launchctl bootstrap "$DOMAIN" "$PLIST"
    echo "Scheduled for the 1st of every month at 09:00. Log: $LOG" ;;
  --run-now)
    launchctl kickstart "$DOMAIN/$LABEL"
    echo "Started. Result in $LOG" ;;
  --remove)
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    echo "Schedule removed." ;;
  *) echo "usage: scripts/schedule_ofcom_check.sh --install | --run-now | --remove"; exit 2 ;;
esac
