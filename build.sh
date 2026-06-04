#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT="$SCRIPT_DIR/MeetingReminder"

swiftc \
  -O \
  -o "$OUTPUT" \
  "$SCRIPT_DIR/MeetingReminder.swift" \
  -framework AppKit \
  -framework EventKit \
  -framework Foundation

echo "Built: $OUTPUT"
