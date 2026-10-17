#!/bin/bash
# Switch between your own SpacePigeon setup and a separate profile.
#
#   scripts/profile.sh demo           open the app on the demo profile (sample presets)
#   scripts/profile.sh fresh --reset  open the app as a new user sees it (default config)
#   scripts/profile.sh <name>         open the app on any profile
#   scripts/profile.sh off            go back to your own setup
#   scripts/profile.sh status         show which profile Hammerspoon loads
#
# A profile only becomes active in Hammerspoon when you press "Save & Reload"
# in the config editor (or "Install & Reload"). Its files live in
# ~/.hammerspoon/spacepigeon_profiles/<name>/; your own config is not touched.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP="$PROJECT_ROOT/SpacePigeon.app"
HS="$HOME/.hammerspoon"
MARKER="$HS/spacepigeon_profile"

reload_hammerspoon() {
    open -g "hammerspoon://reloadConfig" 2>/dev/null || true
}

case "${1:-status}" in
    status)
        if [ -f "$MARKER" ]; then
            echo "Hammerspoon loads the \"$(cat "$MARKER")\" profile ($HS/spacepigeon_profiles/$(cat "$MARKER"))."
        else
            echo "Hammerspoon loads your own setup ($HS/lua/config.lua)."
        fi
        ;;
    off|default)
        rm -f "$MARKER"
        reload_hammerspoon
        echo "Back to your own setup. Hammerspoon is reloading."
        ;;
    *)
        name="$1"
        if [[ ! "$name" =~ ^[A-Za-z0-9_-]+$ ]]; then
            echo "Profile names can only have letters, digits, - and _." >&2
            exit 1
        fi
        if [ "$2" = "--reset" ]; then
            rm -rf "$HS/spacepigeon_profiles/$name"
            echo "Reset the \"$name\" profile."
        fi
        if [ ! -d "$APP" ]; then
            echo "Building SpacePigeon.app first..."
            bash "$SCRIPT_DIR/build_app.sh" >/dev/null
        fi
        # -n: a second instance, so it works next to an already open SpacePigeon.
        open -n "$APP" --args --profile "$name"
        echo "Opened SpacePigeon on the \"$name\" profile. Press \"Save & Reload\" in the config editor to make Hammerspoon use it."
        echo "Run \"scripts/profile.sh off\" to go back to your own setup."
        ;;
esac
