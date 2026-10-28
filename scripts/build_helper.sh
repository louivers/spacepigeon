#!/bin/bash
# Builds the spacectl helper (moves windows between Spaces with SIP enabled).
# Usage: scripts/build_helper.sh [output-path]   (default: build/spacectl)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT="${1:-$PROJECT_ROOT/build/spacectl}"

mkdir -p "$(dirname "$OUT")"

# AppKit is linked on purpose: the window server ignores the bridged move
# operation from processes that have not loaded it.
# Universal (Intel and Apple Silicon). SkyLight is a private framework the
# SDK has no stubs for, so its functions are not linked: they are looked up
# when the helper starts, in the SkyLight that AppKit loads.
clang -O2 -Wall -fno-objc-arc \
  -arch arm64 -arch x86_64 \
  -mmacosx-version-min=12.0 \
  "$PROJECT_ROOT/helper/spacectl.m" \
  -o "$OUT" \
  -framework AppKit -framework ApplicationServices \
  -Wl,-undefined,dynamic_lookup

# Ad-hoc signed unless build_app.sh passes a Developer ID in SIGN_IDENTITY.
# Notarization also needs the hardened runtime and a secure timestamp.
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if [ "$SIGN_IDENTITY" = "-" ]; then
  codesign --force --sign - "$OUT"
else
  codesign --force --options runtime "${SIGN_TIMESTAMP:---timestamp=none}" --sign "$SIGN_IDENTITY" "$OUT"
fi
echo "Built $OUT"
