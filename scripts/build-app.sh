#!/usr/bin/env bash
# Builds an optimized Recall.app into ./build (ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."

ICON="Resources/AppIcon.icns"
[[ -f "$ICON" ]] || { echo "error: $ICON is missing (generate it with: swift scripts/make-icon.swift)" >&2; exit 1; }

# UNIVERSAL=1 builds for Apple silicon and Intel (needs Xcode); otherwise this Mac's architecture.
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    FLAGS=(-c release --arch arm64 --arch x86_64)
else
    FLAGS=(-c release)
fi
swift build "${FLAGS[@]}"
BINARY="$(swift build "${FLAGS[@]}" --show-bin-path)/Recall"

APP="build/Recall.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Recall"
strip -x "$APP/Contents/MacOS/Recall"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Recall</string>
    <key>CFBundleDisplayName</key><string>Recall</string>
    <key>CFBundleIdentifier</key><string>local.recall.app</string>
    <key>CFBundleExecutable</key><string>Recall</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
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
