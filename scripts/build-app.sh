#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/swift.sh build -c release
BIN_DIR="$(./scripts/swift.sh build -c release --show-bin-path)"
APP="$(pwd)/dist/Prompt Pin.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/PromptPin" "$APP/Contents/MacOS/PromptPin"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PromptPin</string>
<key>CFBundleIdentifier</key><string>com.99mrliu.prompt-pin</string>
<key>CFBundleName</key><string>Prompt Pin</string>
<key>CFBundleDisplayName</key><string>Prompt Pin</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>AppIcon</string>
</dict></plist>
PLIST
./scripts/swift.sh compile scripts/make-icon.swift -o .build/make-icon
.build/make-icon "$APP/Contents/Resources"
codesign --force --deep --sign - "$APP"
echo "Built: $APP"
