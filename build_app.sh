#!/bin/bash
set -e

APP_NAME="SpacePigeon"
APP_DIR="${APP_NAME}.app"
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
# Run swift script to generate icon.png
swift generate_icon.swift

# Create iconset
ICONSET="SpacePigeon.iconset"
rm -rf "$ICONSET"
mkdir "$ICONSET"

# Resize to standard icon sizes
sips -z 16 16     icon.png --out "${ICONSET}/icon_16x16.png" > /dev/null
sips -z 32 32     icon.png --out "${ICONSET}/icon_16x16@2x.png" > /dev/null
sips -z 32 32     icon.png --out "${ICONSET}/icon_32x32.png" > /dev/null
sips -z 64 64     icon.png --out "${ICONSET}/icon_32x32@2x.png" > /dev/null
sips -z 128 128   icon.png --out "${ICONSET}/icon_128x128.png" > /dev/null
sips -z 256 256   icon.png --out "${ICONSET}/icon_128x128@2x.png" > /dev/null
sips -z 256 256   icon.png --out "${ICONSET}/icon_256x256.png" > /dev/null
sips -z 512 512   icon.png --out "${ICONSET}/icon_256x256@2x.png" > /dev/null
sips -z 512 512   icon.png --out "${ICONSET}/icon_512x512.png" > /dev/null
cp icon.png "${ICONSET}/icon_512x512@2x.png"

# Convert to .icns
iconutil -c icns "$ICONSET"
cp SpacePigeon.icns "$RESOURCES/AppIcon.icns"

# Cleanup icon artifacts
rm -rf "$ICONSET" icon.png SpacePigeon.icns

# 3. Create Info.plist (Metadata)
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
swiftc launcher.swift -o "$MACOS/launcher"

# 5. Copy Resources (Your Lua Scripts)
echo "📦 Copying Lua scripts..."
cp init.lua layout.lua space_utils.lua workspaces.lua config.lua "$RESOURCES/"

# 6. Ad-Hoc Code Signing
echo "✍️  Signing app (Ad-Hoc)..."
codesign --force --deep --sign - "$APP_DIR"

# 7. Zip it for distribution (using ditto for better macOS compatibility)
echo "🤐 Zipping into ${APP_NAME}.zip..."
rm -f "${APP_NAME}.zip"
ditto -c -k --keepParent "$APP_DIR" "${APP_NAME}.zip"

echo "✅ Done! You can now distribute ${APP_NAME}.zip"