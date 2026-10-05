#!/bin/sh
# Builds MCKeyFix.app (menu bar only) into ./build.
#   SIGN_IDENTITY=<name> signs with that keychain identity instead of ad-hoc.
#   UNIVERSAL=1 builds for arm64 and x86_64.
set -eu
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.1}"
APP="build/MCKeyFix.app"
BUNDLE_ID="dev.mckeyfix.app"
MIN_MACOS="11.0"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if [ "${UNIVERSAL:-0}" = "1" ]; then ARCHS="arm64 x86_64"; else ARCHS="$(uname -m)"; fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

SLICES=""
for ARCH in $ARCHS; do
    swiftc -O -swift-version 5 -target "$ARCH-apple-macos$MIN_MACOS" main.swift -o "build/MCKeyFix-$ARCH"
    SLICES="$SLICES build/MCKeyFix-$ARCH"
done
lipo -create $SLICES -output "$APP/Contents/MacOS/MCKeyFix"
rm $SLICES

# mckeyfix.icon is an Icon Composer document. actool turns it into Assets.car (Liquid Glass) plus an .icns fallback.
xcrun actool mckeyfix.icon --compile "$APP/Contents/Resources" --app-icon mckeyfix \
    --platform macosx --minimum-deployment-target "$MIN_MACOS" \
    --output-partial-info-plist "$(mktemp -d)/icon.plist" > /dev/null

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>MCKeyFix</string>
    <key>CFBundleDisplayName</key><string>MCKeyFix</string>
    <key>CFBundleExecutable</key><string>MCKeyFix</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>mckeyfix</string>
    <key>CFBundleIconName</key><string>mckeyfix</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>Not affiliated with Mojang or Microsoft.</string>
</dict>
</plist>
PLIST

codesign --force --timestamp=none --sign "$SIGN_IDENTITY" "$APP"
echo "Built $APP (signed: $SIGN_IDENTITY)"
