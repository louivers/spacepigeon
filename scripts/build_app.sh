#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_NAME="SpacePigeon"
MIN_MACOS="12.0" # SwiftUI features used by the config editor
APP_DIR="$PROJECT_ROOT/${APP_NAME}.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

# 0. Pick how to sign: the first Developer ID in the keychain, else ad-hoc.
# --notarize also sends the app to Apple and staples the ticket to it. It uses
# the notarytool profile in NOTARY_PROFILE (default "spacepigeon").
NOTARIZE=0
[ "$1" = "--notarize" ] && NOTARIZE=1
NOTARY_PROFILE="${NOTARY_PROFILE:-spacepigeon}"
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning | grep -o -m1 '"Developer ID Application: [^"]*"' | tr -d '"')"
fi
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if [ "$NOTARIZE" = 1 ] && [ "$SIGN_IDENTITY" = "-" ]; then
    echo "❌ --notarize needs a Developer ID Application certificate in the keychain." >&2
    exit 1
fi
# Notarization needs a secure timestamp, which needs a network connection, so
# local builds leave it out and also work offline.
if [ "$NOTARIZE" = 1 ]; then SIGN_TIMESTAMP="--timestamp"; else SIGN_TIMESTAMP="--timestamp=none"; fi
export SIGN_IDENTITY SIGN_TIMESTAMP

echo "🚧 Building $APP_NAME.app..."

# 1. Create Directory Structure
rm -rf "$APP_DIR"
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"

# 2. Generate Icon
echo "🎨 Generating App Icon..."
swift "$PROJECT_ROOT/swift/generate_icon.swift"

ICONSET="$PROJECT_ROOT/SpacePigeon.iconset"
rm -rf "$ICONSET"
mkdir "$ICONSET"

sips -z 16 16     "$PROJECT_ROOT/icon.png" --out "${ICONSET}/icon_16x16.png" > /dev/null
sips -z 32 32     "$PROJECT_ROOT/icon.png" --out "${ICONSET}/icon_16x16@2x.png" > /dev/null
sips -z 32 32     "$PROJECT_ROOT/icon.png" --out "${ICONSET}/icon_32x32.png" > /dev/null
sips -z 64 64     "$PROJECT_ROOT/icon.png" --out "${ICONSET}/icon_32x32@2x.png" > /dev/null
sips -z 128 128   "$PROJECT_ROOT/icon.png" --out "${ICONSET}/icon_128x128.png" > /dev/null
sips -z 256 256   "$PROJECT_ROOT/icon.png" --out "${ICONSET}/icon_128x128@2x.png" > /dev/null
sips -z 256 256   "$PROJECT_ROOT/icon.png" --out "${ICONSET}/icon_256x256.png" > /dev/null
sips -z 512 512   "$PROJECT_ROOT/icon.png" --out "${ICONSET}/icon_256x256@2x.png" > /dev/null
sips -z 512 512   "$PROJECT_ROOT/icon.png" --out "${ICONSET}/icon_512x512.png" > /dev/null
cp "$PROJECT_ROOT/icon.png" "${ICONSET}/icon_512x512@2x.png"

iconutil -c icns "$ICONSET"
cp "$PROJECT_ROOT/SpacePigeon.icns" "$RESOURCES/AppIcon.icns"

rm -rf "$ICONSET" "$PROJECT_ROOT/icon.png" "$PROJECT_ROOT/SpacePigeon.icns"

# 3. Create Info.plist
cat > "$CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>launcher</string>
    <key>CFBundleIdentifier</key>
    <string>com.louivers.spacepigeon</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.2.2</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>SpacePigeon asks Hammerspoon to reload after you save your workspaces.</string>
</dict>
</plist>
EOF

# 4. Compile Swift Launcher
echo "🔨 Compiling Swift launcher..."
# Universal: built for Intel and Apple Silicon, then merged into one binary.
SOURCES=("$PROJECT_ROOT/swift/launcher.swift" "$PROJECT_ROOT/swift/ConfigUI.swift" "$PROJECT_ROOT/swift/AppPicker.swift" "$PROJECT_ROOT/swift/Profile.swift" "$PROJECT_ROOT/swift/LogUI.swift")
SLICES="$(mktemp -d)"
for ARCH in arm64 x86_64; do
    swiftc -O -target "$ARCH-apple-macos$MIN_MACOS" "${SOURCES[@]}" -o "$SLICES/launcher-$ARCH"
done
lipo -create "$SLICES/launcher-arm64" "$SLICES/launcher-x86_64" -output "$MACOS/launcher"
rm -rf "$SLICES"

# 4b. Build the spacectl helper (moves windows between Spaces, SIP stays on)
echo "🛠  Building spacectl helper..."
bash "$SCRIPT_DIR/build_helper.sh" "$RESOURCES/bin/spacectl"

# 5. Copy Resources
echo "📦 Copying Lua sources..."
mkdir -p "$RESOURCES/lua"
cp "$PROJECT_ROOT/init.lua" "$RESOURCES/"
cp "$PROJECT_ROOT/lua/"*.lua "$RESOURCES/lua/"

# 6. Signing
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "✍️  Signing app (ad-hoc, no Developer ID in the keychain)"
else
    echo "✍️  Signing app as $SIGN_IDENTITY"
fi
xattr -cr "$APP_DIR"
# Sign the whole bundle, not just the executable, so macOS sees a complete,
# valid app (the helper in Resources/bin is already signed by build_helper.sh).
if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --force --sign - "$APP_DIR"
else
    # The hardened runtime is required for notarization. It blocks Apple
    # Events unless the entitlements allow them, and the app uses AppleScript
    # to ask Hammerspoon to reload.
    codesign --force --options runtime "$SIGN_TIMESTAMP" \
        --entitlements "$PROJECT_ROOT/swift/SpacePigeon.entitlements" \
        --sign "$SIGN_IDENTITY" "$APP_DIR"
fi

# Tell Launch Services and Spotlight about the app, so launchers like
# Raycast and Spotlight list it.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -f "$APP_DIR" >/dev/null 2>&1 || true
if [ -d "/Applications/${APP_NAME}.app" ]; then
    "$LSREGISTER" -f "/Applications/${APP_NAME}.app" >/dev/null 2>&1 || true
    mdimport "/Applications/${APP_NAME}.app" >/dev/null 2>&1 || true
fi

# 7. Zip for distribution
echo "🤐 Zipping into ${APP_NAME}.zip..."
ZIP="$PROJECT_ROOT/${APP_NAME}.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP_DIR" "$ZIP"

# 8. Notarize (only with --notarize). Apple checks the zip, the ticket is
# stapled to the app so Gatekeeper accepts it offline too, and the app is
# zipped again with the ticket in it.
if [ "$NOTARIZE" = 1 ]; then
    echo "📮 Notarizing (usually takes a few minutes)..."
    RESULT="$(mktemp)"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$RESULT"
    STATUS="$(plutil -extract status raw -o - "$RESULT")"
    if [ "$STATUS" != "Accepted" ]; then
        echo "❌ Notarization status: $STATUS. Apple's log:" >&2
        xcrun notarytool log "$(plutil -extract id raw -o - "$RESULT")" --keychain-profile "$NOTARY_PROFILE" >&2 || true
        rm -f "$RESULT"
        exit 1
    fi
    rm -f "$RESULT"
    xcrun stapler staple "$APP_DIR"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP_DIR" "$ZIP"
    spctl --assess --type execute "$APP_DIR"
    echo "🛂 Notarized, and Gatekeeper accepts the app"
fi

echo "✅ Done! You can now distribute ${APP_NAME}.zip"
