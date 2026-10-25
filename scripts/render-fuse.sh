#!/usr/bin/env bash
# Renders the menu bar fuse to dist/fuse.png (every state and move) and dist/fuse.gif (a whole session).
# The same drawing as the menu bar and the Xcode previews in LunteApp/Sources/FuseKit.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist
swiftc -O -o dist/render-fuse LunteApp/Sources/FuseKit/MenuFuse.swift scripts/render-fuse.swift
dist/render-fuse sheet dist/fuse.png
dist/render-fuse gif dist/fuse.gif
