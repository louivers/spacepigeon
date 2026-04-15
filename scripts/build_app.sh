#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_NAME="SpacePigeon"
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
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.10</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
EOF

# 4. Compile Swift Launcher
echo "🔨 Compiling Swift launcher..."
swiftc "$PROJECT_ROOT/swift/launcher.swift" "$PROJECT_ROOT/swift/ConfigUI.swift" -o "$MACOS/launcher"

# 5. Copy Resources
echo "📦 Copying Lua sources..."
mkdir -p "$RESOURCES/lua"
cp "$PROJECT_ROOT/init.lua" "$RESOURCES/"
cp "$PROJECT_ROOT/lua/"*.lua "$RESOURCES/lua/"

# 6. Ad-Hoc Signing
echo "✍️  Signing app"
xattr -cr "$APP_DIR"
codesign --force --sign - "$MACOS/launcher"

# 7. Zip for distribution
echo "🤐 Zipping into ${APP_NAME}.zip..."
rm -f "$PROJECT_ROOT/${APP_NAME}.zip"
ditto -c -k --keepParent "$APP_DIR" "$PROJECT_ROOT/${APP_NAME}.zip"

echo "✅ Done! You can now distribute ${APP_NAME}.zip"
