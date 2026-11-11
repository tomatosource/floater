#!/bin/bash
# Builds build/Floater.app (a SwiftPM release build wrapped in an app bundle). Run via `make build`.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP=build/Floater.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Floater "$APP/Contents/MacOS/Floater"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.tomatosource.floater</string>
    <key>CFBundleName</key><string>Floater</string>
    <key>CFBundleExecutable</key><string>Floater</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
echo "Built $APP"

