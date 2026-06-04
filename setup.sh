#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
chmod +x "$SCRIPT_DIR/build_reminder_app.sh" "$SCRIPT_DIR/meeting_reminder.py"
"$SCRIPT_DIR/build_reminder_app.sh"

echo ""
echo "双击运行，或执行："
echo "  open \"$SCRIPT_DIR/MeetingReminder.app\""
