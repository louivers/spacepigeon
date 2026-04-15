#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET_DIR="$HOME/.hammerspoon"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="${TARGET_DIR}_backup_${TIMESTAMP}"

echo "=== SpacePigeon Deploy ==="
echo "Source: $PROJECT_ROOT"
echo "Target: $TARGET_DIR"

if [ -d "$TARGET_DIR" ]; then
    echo "Creating backup at $BACKUP_DIR..."
    cp -R "$TARGET_DIR" "$BACKUP_DIR"
else
    echo "Creating target directory..."
    mkdir -p "$TARGET_DIR"
fi

echo "Copying files..."
mkdir -p "$TARGET_DIR/lua"
cp "$PROJECT_ROOT/init.lua" "$TARGET_DIR/"
cp "$PROJECT_ROOT/lua/"*.lua "$TARGET_DIR/lua/"

echo "Deployment complete!"
echo "Hammerspoon should detect the changes and reload automatically."
