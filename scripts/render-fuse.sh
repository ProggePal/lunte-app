#!/usr/bin/env bash
# Renders the menu bar fuse to dist/fuse.png (every state and move) and dist/fuse.gif (a whole session), and the app's
# icon, Resources/Lunte.icns. With move names from FusePreviews.moves, such as render-fuse.sh "Close call" Blows, just
# those, magnified: frame by frame to dist/moves.png, and at real speed to dist/moves.gif. render-fuse.sh blast draws
# the whole Boom of each kind on a stand-in screen, and a close call, to dist/blast-<kind>.png and .mp4, and all of
# them in dist/blast.mp4; render-fuse.sh blast willow 1.25 close draws just those.
# render-fuse.sh tour plays every move and every sound in one session, to dist/tour.mp4 (and its mix, dist/tour.wav);
# render-fuse.sh tour synth does it with the synthesised flame instead of Resources/fuse.wav, to dist/tour-synth.mp4.
# The same drawing as the menu bar and the Xcode previews in LunteApp/Sources/FuseKit.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist
swiftc -O -o dist/render-fuse LunteApp/Sources/FuseKit/*.swift scripts/render-fuse.swift
if [ "${1:-}" = blast ]; then
  shift
  rm -f dist/blast-list.txt
  dist/render-fuse blast dist/blast "$@" | while read -r frames; do
    ffmpeg -nostdin -loglevel error -y -framerate 50 -i "$frames/f%04d.png" -c:v libx264 -pix_fmt yuv420p -crf 18 "$frames.mp4"
    echo "file '$(basename "$frames").mp4'" >> dist/blast-list.txt
    rm -r "$frames"
    echo "$frames.mp4"
  done
  ffmpeg -loglevel error -y -f concat -safe 0 -i dist/blast-list.txt -c copy dist/blast.mp4 && rm dist/blast-list.txt
  exit
fi
if [ "${1:-}" = tour ]; then exec dist/render-fuse tour dist/tour ${2:-}; fi
if [ $# -gt 0 ]; then exec dist/render-fuse moves dist/moves "$@"; fi
dist/render-fuse sheet dist/fuse.png
dist/render-fuse gif dist/fuse.gif
rm -rf dist/Lunte.iconset
dist/render-fuse icon dist/Lunte.iconset
iconutil -c icns dist/Lunte.iconset -o Resources/Lunte.icns
