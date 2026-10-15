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
for f in "$PROJECT_ROOT/lua/"*.lua; do
    name="$(basename "$f")"
    # Never overwrite the user's own config (the config editor writes it).
    if [ "$name" = "config.lua" ] && [ -f "$TARGET_DIR/lua/config.lua" ]; then
        echo "Keeping existing lua/config.lua"
        continue
    fi
    cp "$f" "$TARGET_DIR/lua/"
done

echo "Building spacectl helper..."
if ! bash "$SCRIPT_DIR/build_helper.sh" "$TARGET_DIR/bin/spacectl"; then
    echo "Helper build failed: SpacePigeon will fall back to Mission Control and relaunching apps."
fi

echo "Reloading Hammerspoon..."
open -g "hammerspoon://reloadConfig" || echo "Could not reload: reload Hammerspoon by hand."

echo "Deployment complete!"
