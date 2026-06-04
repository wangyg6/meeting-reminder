#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$SCRIPT_DIR/MeetingReminder.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "Building icon..."
chmod +x "$SCRIPT_DIR/build_icon.sh"
"$SCRIPT_DIR/build_icon.sh"

echo "Building banner..."
"$SCRIPT_DIR/build_banner.sh"
"$SCRIPT_DIR/build_app.sh"

echo "Building MeetingReminder.app..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"

clang -O2 -framework Cocoa -o "$MACOS/MeetingReminder" "$SCRIPT_DIR/app_main.m" "$SCRIPT_DIR/preferences.m"

cp "$SCRIPT_DIR/meeting_reminder.py" "$RESOURCES/"
cp "$SCRIPT_DIR/config.default.json" "$RESOURCES/"
cp "$SCRIPT_DIR/show_banner" "$RESOURCES/"
cp "$SCRIPT_DIR/AppIcon.icns" "$RESOURCES/"
cp -R "$SCRIPT_DIR/MeetingBanner.app" "$RESOURCES/"

cat > "$CONTENTS/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>MeetingReminder</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.meetingreminder.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Meeting Reminder</string>
    <key>CFBundleDisplayName</key>
    <string>Meeting Reminder</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>需要读取日历中的会议信息以在会议开始前提醒您。</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
</dict>
</plist>
EOF

echo ""
echo "Built: $APP_DIR"
echo "Run: open \"$APP_DIR\""
