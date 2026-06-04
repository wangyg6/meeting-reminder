#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SCRIPT_DIR/assets/AppIcon.png"
SQUARE="$SCRIPT_DIR/assets/AppIcon-square.png"
ICONSET="$SCRIPT_DIR/AppIcon.iconset"
OUT="$SCRIPT_DIR/AppIcon.icns"

if [[ ! -f "$SRC" ]]; then
  echo "Missing $SRC"
  exit 1
fi

# Read dimensions
read -r W H < <(sips -g pixelWidth -g pixelHeight "$SRC" 2>/dev/null | awk '/pixel/{print $2}' | paste - - | tr '\t' ' ')
W=${W:-1024}
H=${H:-1024}

# Pad to square (no stretch) using edge color, then downscale master
MAX=$(( W > H ? W : H ))
sips -p "$MAX" "$MAX" "$SRC" --out "$SQUARE" >/dev/null

# Master 1024x1024 for sharp icns
MASTER="$SCRIPT_DIR/assets/AppIcon-1024.png"
sips -z 1024 1024 "$SQUARE" --out "$MASTER" >/dev/null

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

sizes=(16 32 128 256 512)
for size in "${sizes[@]}"; do
  sips -z "$size" "$size" "$MASTER" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$MASTER" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$OUT"
rm -rf "$ICONSET"
echo "Built: $OUT (from ${W}x${H} -> 1024x1024 square)"
