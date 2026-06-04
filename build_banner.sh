#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT="$SCRIPT_DIR/show_banner"

clang -O2 -framework Cocoa -o "$OUTPUT" "$SCRIPT_DIR/banner.m"

echo "Built: $OUTPUT"
echo "Test: $OUTPUT \"产品评审会\\n📍 3楼会议室 A301 · 5 分钟后\""
