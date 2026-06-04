#!/bin/bash
set -euo pipefail

PID="/tmp/meeting-reminder.pid"

stop_pid() {
  local pid="$1"
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid"
    echo "Stopped pid $pid"
  fi
}

if [ -f "$PID" ]; then
  stop_pid "$(cat "$PID")"
  rm -f "$PID"
fi

launchctl bootout "gui/$(id -u)/com.meetingreminder.agent" 2>/dev/null && echo "Stopped launchd service" || true

pkill -f "meeting_reminder.py" 2>/dev/null && echo "Stopped meeting_reminder.py" || true
