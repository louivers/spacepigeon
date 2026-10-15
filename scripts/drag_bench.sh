#!/bin/bash
# Runs the drag test (lua/dragbench.lua) in Hammerspoon.
#   ./scripts/drag_bench.sh            full test (384 approaches, 3 rounds)
#   ./scripts/drag_bench.sh --smoke    4 approaches, 1 round: checks the test works
#   ./scripts/drag_bench.sh --rounds 5
#   ./scripts/drag_bench.sh --kinds between-right,far-left
#     (moves: between-left, between-right, far-left, far-right)
# Needs at least 4 fullscreen apps on the main screen: run a workspace first.
# Don't touch the mouse while it runs. Stop with cmd+alt+ctrl+X.
# Results: ~/.hammerspoon/dragbench/<time>.md (ranking) and .csv (every drag).
set -e
query=""
while [ $# -gt 0 ]; do
    case "$1" in
        --smoke) query="${query}&smoke=1" ;;
        --rounds) shift; query="${query}&rounds=$1" ;;
        --kinds) shift; query="${query}&kinds=$1" ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
    shift
done
open -g "hammerspoon://dragbench?${query#&}"
echo "Drag test started. Don't touch the mouse; stop with cmd+alt+ctrl+X."
echo "Results will be in ~/.hammerspoon/dragbench/"
