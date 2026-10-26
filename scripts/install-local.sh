#!/usr/bin/env bash
# Builds Lunte and installs it on this Mac: quits the running copy, replaces /Applications/Lunte.app, and opens it.
# Opening it points Claude Code's hook at it, so this copy plays your real game. A debug build, signed ad-hoc.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build-app.sh | grep -E "error|Built"
osascript -e 'quit app "Lunte"' 2>/dev/null || true
sleep 1
rm -rf /Applications/Lunte.app
ditto dist/Lunte.app /Applications/Lunte.app
open /Applications/Lunte.app
sleep 2
pgrep -x Lunte >/dev/null && echo "running; hook: $(readlink "$HOME/Library/Application Support/Lunte/lunte-hook")"
