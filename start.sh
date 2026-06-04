#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="/tmp/meeting-reminder.log"
PID="/tmp/meeting-reminder.pid"

if [ -f "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; then
  echo "Already running (pid $(cat "$PID"))"
  exit 0
fi

nohup /usr/bin/python3 "$SCRIPT_DIR/meeting_reminder.py" >> "$LOG" 2>&1 &
echo $! > "$PID"
sleep 1

if kill -0 "$(cat "$PID")" 2>/dev/null; then
  echo "Started in background (pid $(cat "$PID"))"
  echo "Log: tail -f $LOG"
  tail -2 "$LOG" 2>/dev/null || true
else
  echo "Failed to start. Check $LOG"
  exit 1
fi
