#!/usr/bin/env bash
# Renders the menu bar fuse to dist/fuse.png (every state and move) and dist/fuse.gif (a whole session). With move names
# from FusePreviews.moves, such as render-fuse.sh "Close call" Blows, just those, magnified: frame by frame to
# dist/moves.png, and at real speed to dist/moves.gif.
# The same drawing as the menu bar and the Xcode previews in LunteApp/Sources/FuseKit.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist
swiftc -O -o dist/render-fuse LunteApp/Sources/FuseKit/MenuFuse.swift scripts/render-fuse.swift
if [ $# -gt 0 ]; then exec dist/render-fuse moves dist/moves "$@"; fi
dist/render-fuse sheet dist/fuse.png
dist/render-fuse gif dist/fuse.gif
