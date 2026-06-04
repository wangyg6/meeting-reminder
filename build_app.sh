#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$SCRIPT_DIR/MeetingBanner.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"

"$SCRIPT_DIR/build_banner.sh"

rm -rf "$APP_DIR"
mkdir -p "$MACOS"

cat > "$CONTENTS/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>meeting-banner</string>
    <key>CFBundleIdentifier</key>
    <string>com.meetingreminder.banner</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MeetingBanner</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

cat > "$MACOS/meeting-banner" <<EOF
#!/bin/bash
ROOT="\$(cd "\$(dirname "\$0")/../../.." && pwd)"
MSG_FILE="/tmp/meeting-reminder-msg.txt"
if [ -f "\$MSG_FILE" ]; then
  TEXT="\$(cat "\$MSG_FILE")"
elif [ -n "\$1" ]; then
  TEXT="\$1"
fi
if [ -z "\$TEXT" ]; then
  TEXT="Meeting Reminder"
fi

echo "\$(date '+%Y-%m-%d %H:%M:%S') banner: \$TEXT" >> /tmp/meeting-reminder-banner.log
exec "\$ROOT/show_banner" "\$TEXT"
EOF

chmod +x "$MACOS/meeting-banner"

echo "Built: $APP_DIR"
echo ""
echo "Test:"
echo "  open -W -n \"$APP_DIR\" --args \"产品评审会\n📍 3楼会议室 A301 · 5 分钟后\""
