#!/bin/zsh
# Builds MCKeyFix.app (menu bar only, no Dock icon).
set -euo pipefail
cd "${0:A:h}"

APP=MCKeyFix.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -swift-version 5 main.swift -o "$APP/Contents/MacOS/MCKeyFix"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.mckeyfix</string>
    <key>CFBundleName</key><string>MCKeyFix</string>
    <key>CFBundleExecutable</key><string>MCKeyFix</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
echo "Built $PWD/$APP"
