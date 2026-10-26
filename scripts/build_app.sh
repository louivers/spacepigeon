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
    <string>2.2.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
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

# 6. Ad-Hoc Signing
echo "✍️  Signing app"
xattr -cr "$APP_DIR"
# Sign the whole bundle, not just the executable, so macOS sees a complete,
# valid app (the helper in Resources/bin is already signed by build_helper.sh).
codesign --force --sign - "$APP_DIR"

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
rm -f "$PROJECT_ROOT/${APP_NAME}.zip"
ditto -c -k --keepParent "$APP_DIR" "$PROJECT_ROOT/${APP_NAME}.zip"

echo "✅ Done! You can now distribute ${APP_NAME}.zip"
