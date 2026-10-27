#!/usr/bin/env bash
# Renders the popover in every preview state, light and dark, to dist/popover/*.png: the same states as the Xcode
# previews in LunteApp/Sources/Lunte/Previews.swift. Nothing is watched, polled or sent. Then, with ffmpeg, contact
# sheets of the numbered states, four to a row: dist/sheet-light.png and dist/sheet-dark.png.
# Name states to draw just those, by how their names start: `scripts/render-popover.sh 9b pill-lab`. The pill lab's
# replay frames take minutes, so they're drawn only when named: `scripts/render-popover.sh replay`.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build-app.sh | grep -E "error|Built" # quiet, but a failed build still says why
rm -rf dist/popover
dist/Lunte.app/Contents/MacOS/Lunte -PopoverShots "$PWD/dist/popover" -PopoverOnly "$*"
ls dist/popover
command -v ffmpeg >/dev/null || { echo "no ffmpeg, so no contact sheets"; exit 0; }
cd dist/popover
for mode in light dark; do
  files=($(ls | grep -E "^[0-9]+-.*-$mode\.png$" | sort -V))
  (( ${#files[@]} < 2 )) && continue # a sheet takes two
  w=0 h=0
  for f in "${files[@]}"; do
    set -- $(sips -g pixelWidth -g pixelHeight "$f" | awk '/pixel/ {print $2}')
    (( $1 > w )) && w=$1; (( $2 > h )) && h=$2
  done
  args=() pads="" cells="" layout=""
  for i in "${!files[@]}"; do
    args+=(-i "${files[$i]}")
    pads+="[$i:v]pad=$((w + 20)):$((h + 20)):10:10:color=gray[p$i];"
    cells+="[p$i]"
    layout+="$((i % 4 * (w + 20)))_$((i / 4 * (h + 20)))|"
  done
  ffmpeg -loglevel error -y "${args[@]}" -filter_complex "$pads${cells}xstack=inputs=${#files[@]}:layout=${layout%|}:fill=gray" ../sheet-$mode.png
  echo "dist/sheet-$mode.png"
done
