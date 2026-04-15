#!/bin/bash

# Define paths
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$HOME/.hammerspoon"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="${TARGET_DIR}_backup_${TIMESTAMP}"

echo "=== SpacePigeon Deploy ==="
echo "Source: $SOURCE_DIR"
echo "Target: $TARGET_DIR"

# 1. Backup existing configuration
if [ -d "$TARGET_DIR" ]; then
    echo "Creating backup at $BACKUP_DIR..."
    cp -R "$TARGET_DIR" "$BACKUP_DIR"
else
    echo "Creating target directory..."
    mkdir -p "$TARGET_DIR"
fi

# 2. Copy Lua files
echo "Copying files..."
mkdir -p "$TARGET_DIR/lua"
cp "$SOURCE_DIR/init.lua" "$TARGET_DIR/"
cp "$SOURCE_DIR/lua/"*.lua "$TARGET_DIR/lua/"

echo "Deployment complete!"
echo "Hammerspoon should detect the changes and reload automatically."

