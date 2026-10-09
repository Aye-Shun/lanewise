#!/usr/bin/env bash
# Builds an optimized Recall.app into ./build (ad-hoc signed, runs on this Mac).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/Recall.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Recall "$APP/Contents/MacOS/Recall"
strip -x "$APP/Contents/MacOS/Recall"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Recall</string>
    <key>CFBundleDisplayName</key><string>Recall</string>
    <key>CFBundleIdentifier</key><string>local.recall.app</string>
    <key>CFBundleExecutable</key><string>Recall</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticTermination</key><false/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP ($(du -sh "$APP" | cut -f1))"
