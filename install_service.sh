#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST_SRC="$SCRIPT_DIR/com.meetingreminder.agent.plist"
PLIST_DST="$HOME/Library/LaunchAgents/com.meetingreminder.agent.plist"
LOG="/tmp/meeting-reminder.log"
PID="/tmp/meeting-reminder.pid"

mkdir -p "$HOME/Library/LaunchAgents"

# Update script path in plist
sed "s|/Users/wangyg6/cursor/demoProject1/meeting-reminder|$SCRIPT_DIR|g" \
  "$PLIST_SRC" > "$PLIST_DST"

launchctl bootout "gui/$(id -u)/com.meetingreminder.agent" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_DST"
launchctl enable "gui/$(id -u)/com.meetingreminder.agent"
launchctl kickstart -k "gui/$(id -u)/com.meetingreminder.agent"

sleep 2
echo "Installed launchd service."
echo "Log: tail -f $LOG"
if [ -f "$LOG" ]; then
  tail -3 "$LOG" || true
fi
