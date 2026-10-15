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
# Built for this Mac's CPU only: SkyLight is a private framework that the
# linker reads from the native system cache.
clang -O2 -Wall -fno-objc-arc \
  -arch "$(uname -m)" \
  -mmacosx-version-min=13.0 \
  "$PROJECT_ROOT/helper/spacectl.m" \
  -o "$OUT" \
  -framework AppKit -framework ApplicationServices \
  -F/System/Library/PrivateFrameworks -framework SkyLight

codesign --force --sign - "$OUT"
echo "Built $OUT"
