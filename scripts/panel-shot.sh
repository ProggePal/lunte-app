#!/usr/bin/env bash
# Opens the real panel under the real menu bar item, from dist/Lunte.app (build it first), with your real game: draws
# it to OUT (default dist/panel.png), prints where it sat against the item and whether the item was lit, and quits.
# The copy in /Applications steps aside meanwhile and opens again after, which points Claude Code's hook back at it.
# The drawing can't show the material's blur: it comes out flat.
set -euo pipefail
cd "$(dirname "$0")/.."
out=${1:-$PWD/dist/panel.png}
running=$(pgrep -x Lunte || true)
osascript -e 'quit app "Lunte"' 2>/dev/null || true
sleep 1
dist/Lunte.app/Contents/MacOS/Lunte -PanelShot "$out" 2>/dev/null | grep '^panel' || true
if [[ -n $running && -d /Applications/Lunte.app ]]; then open /Applications/Lunte.app
else echo "note: Claude Code's hook now points at dist/Lunte.app; scripts/install-local.sh points it back"; fi
echo "$out"
