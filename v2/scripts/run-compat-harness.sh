#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
V2_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

extract_int() {
  local fixture="$1"
  local key="$2"
  /usr/bin/swift -e '
import Foundation
let fixture = CommandLine.arguments[1]
let key = CommandLine.arguments[2]
let data = try Data(contentsOf: URL(fileURLWithPath: fixture))
let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
let req = json["request"] as! [String: Any]
print(req[key] as! Int)
' "$fixture" "$key"
}

run_case() {
  local fixture="$1"
  local main_spaces secondary_spaces
  main_spaces="$(extract_int "$fixture" "mainSpaces")"
  secondary_spaces="$(extract_int "$fixture" "secondarySpaces")"

  echo "Running fixture: $fixture"
  swift run --package-path "$V2_ROOT" spacepigeon reset \
    --main-spaces "$main_spaces" \
    --secondary-spaces "$secondary_spaces" \
    --close-all \
    --dry-run
}

run_case "$V2_ROOT/fixtures/single-display-reset.json"
run_case "$V2_ROOT/fixtures/dual-display-reset.json"

echo "Compatibility harness completed."
