#!/usr/bin/env bash
# The README's clips (docs/clips/<clip>.gif): the top right of a real Mac, the fuse in the menu bar and a small Terminal
# window under it with a real Claude Code in it, zoomed in. Lunte's -HeroDemo plays a set script instead of the game
# (App.swift `clips`): a Terminal window types each prompt into Claude Code, the hook hands it to Lunte, and Claude
# answers it in a line. The prompts go to a spare log, so your game never sees them, and your own Lunte
# steps aside meanwhile. A take is kept in docs/clips/takes, so the GIF can be framed again without a new one.
#   scripts/hero.sh fuse|heat|cool|close|chain|boom|all   a take and its GIF, all being the README's; hands off for
#                                                          half a minute a clip
#   scripts/hero.sh gif <clip>|menubar|all            only the GIF again, from the take
#   scripts/hero.sh bar                               the menu bar with the fuse in it, the README's landing
# Terminal needs Screen Recording (System Settings › Privacy & Security), once. ffmpeg records it: macOS's own
# `screencapture -v` stalls now and then.
set -euo pipefail
cd "$(dirname "$0")/.."

# What each clip types.
prompts() {
  case $1 in
    fuse) printf '%s\n' "why is this still broken" "omg. make no mistakes, idiot" "ok sorry. thanks for sticking with me" \
      "you're a legend, honestly" ;;
    heat) echo "why is this still broken" ;;
    cool) echo "nice, thanks buddy" ;;
    close) printf '%s\n' "this is the third time i've asked" "ok sorry. thanks for sticking with me" ;;
    boom) printf '%s\n' "no, that's not what i meant" "omg. make no mistakes, idiot" "are you kidding me rn" ;;
    chain) printf '%s\n' "are you serious" "UNBELIEVABLE" "i give up" ;;
  esac
}

take() {
  local clip=$1 tail=1 dir screen item=190 m=36 n=12 # pt of wallpaper round the window: left and top, right and bottom
  [[ $clip == boom ]] && tail=4
  # The fuse as near the middle as the menu bar has room for: macOS draws its recording badge over the first 48 pt of
  # the item, so the recording starts past that, and the wider the item, the further the fuse is from that edge. A
  # screen under 1200 pt wide has room for 190 next to the app's menus, and its fuse sits about a quarter across.
  screen=$(osascript -e 'tell application "Finder" to get item 3 of (get bounds of window of desktop)')
  (( screen >= 1200 )) && item=250
  dir=$(mktemp -d)
  prompts "$clip" > "$dir/prompts"
  LUNTE_LOG=$dir/events.jsonl dist/Lunte.app/Contents/MacOS/Lunte -HeroDemo "$clip" -HeroItem $item > "$dir/at" 2> /dev/null &
  local demo=$!
  until grep -q '^at' "$dir/at"; do sleep 0.2; done
  local left right bar
  read -r _ left right bar _ < "$dir/at"
  # A Terminal window as people keep it, 52 x 15 in small type, measured, and the recording that much wider and taller,
  # with some wallpaper round it.
  local win ww wh w h x
  read -r win ww wh <<< "$(osascript -e "tell application \"Terminal\"
    activate
    set t to do script \"cd /tmp/lunte-demo; clear\"
    set current settings of t to settings set \"LunteClip\"
    set font size of settings set \"LunteClip\" to 11
    set number of columns of t to 52
    set number of rows of t to 15
    delay 0.5
    set b to bounds of front window
    return (id of front window as text) & \" \" & (item 3 of b - item 1 of b) & \" \" & (item 4 of b - item 2 of b)
  end tell")"
  w=$(( ww + m + n )) h=$(( bar + 10 + wh + n )) x=$(( left + 52 ))
  # ponytail: a fixed pace instead of watching Claude's screen
  cat > "$dir/take.exp" <<'EOF'
lassign $argv dir rect tail plugin win demo
proc front {} { exec osascript -e "tell application \"Terminal\" to set index of window id $::win to 1" \
  -e {tell application "Terminal" to activate} }
set prompts [split [string trim [read [open $dir/prompts]]] "\n"]
proc pause {ms} { after $ms {set ::tick 1}; vwait ::tick }
proc type {text} { foreach c [split $text ""] { send -- $c; pause 55 } }
stty raw -echo ;# Terminal's answers to Claude's queries would echo on screen
set rows [stty rows]; set cols [stty columns]
# Only Lunte's plugin and the folder's quiet settings, none of yours. Claude answers for itself, in a line, so the
# fuse keeps the attention.
spawn -noecho claude --model sonnet --tools "" --setting-sources project --plugin-dir $plugin \
  --append-system-prompt "Reply in one short sentence."
stty rows $rows columns $cols < $spawn_out(slave,name)
expect -timeout 8 -re {trust} { pause 1000; send "\033\[B"; pause 500; send "\r" } timeout {}
expect_background -re {.+} {} ;# Claude's screen goes through to the window while we wait
pause 2000
# As long as the clip: a second, each prompt typed and stopped, then the tail. It stops itself.
set secs [expr {3.5 + $tail}]
foreach p $prompts { set secs [expr {$secs + [string length $p] * .055 + 4.1}] }
front ;# a focused window's cursor is solid
lassign [split $rect ,] x y w h ;# pt; the screen records in px
set rec [exec ffmpeg -y -loglevel error -f avfoundation -pixel_format bgr0 -framerate 30 -capture_cursor 0 \
  -i "Capture screen 0:none" -t $secs -vf "crop=[expr {$w * 2}]:[expr {$h * 2}]:[expr {$x * 2}]:[expr {$y * 2}]" \
  -c:v libx264 -crf 20 -pix_fmt yuv420p $dir/take.mp4 < /dev/null 2> /dev/null &] ;# AVFoundation's warnings would land on screen
pause 500
front ;# ffmpeg takes the focus as it starts
exec kill -USR1 $demo ;# the fresh fuse comes in
pause 3000
# Each prompt reaches the hook as it's sent, and Claude answers it in a line.
foreach p $prompts { type $p; pause 300; send "\r"; pause 3800 }
while {![catch {exec kill -0 $rec}]} { pause 200 } ;# it writes the movie as it stops
send "/exit\r"
pause 1500
stty -raw echo
exec touch $dir/done
EOF
  osascript -e "tell application \"Terminal\"
    set bounds of window id $win to {$(( x + m )), $(( bar + 10 )), $(( x + m + ww )), $(( bar + 10 + wh ))}
    do script \"clear; export LUNTE_LOG=$dir/events.jsonl; expect $dir/take.exp $dir $x,0,$w,$h $tail $PWD/plugin $win $demo; exit\" in selected tab of window id $win
  end tell" > /dev/null
  until [[ -f $dir/done ]]; do sleep 1; done
  osascript -e "tell application \"Terminal\" to close (every window whose id is $win)" 2>/dev/null || true
  kill $demo
  mkdir -p docs/clips/takes
  mv "$dir/take.mp4" "docs/clips/takes/$clip.mp4"
  gif "$clip"
}

# The take to a GIF that loops: the Claude Code clips as they are, and the menu bar floating on a backdrop with a soft
# shadow, white and dark (-dark.gif), in 200 colours and no dithering, which keep the shadow smooth. The menu bar also
# makes the repo's social preview, docs/social-preview.png, for its Settings.
gif() {
  local dir
  dir=$(mktemp -d)
  mkdir "$dir/in" "$dir/out"
  if [[ $1 == menubar ]]; then
    ffmpeg -loglevel error -i docs/clips/takes/menubar.mp4 -vf fps=15 "$dir/in/t%04d.png"
    dist/render-fuse social "$dir/in" docs/social-preview.png
    local theme out
    for theme in light dark; do
      out=docs/clips/menubar.gif
      [[ $theme == dark ]] && out=docs/clips/menubar-dark.gif
      rm -f "$dir"/out/*
      dist/render-fuse bar "$dir/in" "$dir/out" $theme
      ffmpeg -y -loglevel error -framerate 15 -i "$dir/out/c%04d.png" -filter_complex "
        [0]format=rgb24,split[c][d];
        [c]palettegen=max_colors=200:stats_mode=diff[p];
        [d][p]paletteuse=dither=none:diff_mode=rectangle" "$out"
    done
    rm -rf "$dir"
    ls -lh docs/clips/menubar.gif docs/clips/menubar-dark.gif docs/social-preview.png
    return
  else
    ffmpeg -loglevel error -i "docs/clips/takes/$1.mp4" -vf fps=12 "$dir/in/t%04d.png"
    dist/render-fuse plain "$dir/in" "$dir/out" 1000
    # ponytail: ffmpeg's palette, no gifski; 128 colours dithered, for the wallpaper, the flame and the screen's dimming
    ffmpeg -y -loglevel error -framerate 12 -i "$dir/out/c%04d.png" -filter_complex "
      [0]format=rgb24,split[c][d];
      [c]palettegen=max_colors=128:stats_mode=diff[p];
      [d][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" "docs/clips/$1.gif"
  fi
  rm -rf "$dir"
  ls -lh "docs/clips/$1.gif"
}

# The README's landing, docs/clips/menubar.gif and menubar-dark.gif: the menu bar from the fuse to the clock, recorded from a
# Terminal window as the hook gets four prompts straight, two mean and two kind, which bring the fuse back where it
# started, so it loops. It starts past the item's empty left end, where macOS draws its recording badge, and once the
# screen has left any app in full screen.
bar() {
  local dir left right bar screen x secs=17
  dir=$(mktemp -d)
  LUNTE_LOG=$dir/events.jsonl dist/Lunte.app/Contents/MacOS/Lunte -HeroDemo fuse -HeroItem 190 > "$dir/at" 2> /dev/null &
  local demo=$!
  until grep -q '^at' "$dir/at"; do sleep 0.2; done
  read -r _ left right bar screen < "$dir/at"
  x=$(( left + 52 ))
  cat > "$dir/bar.sh" <<EOF
ffmpeg -y -loglevel error -f avfoundation -pixel_format bgr0 -framerate 30 -capture_cursor 0 -i "Capture screen 0:none" \\
  -t $secs -vf "crop=$(( (screen - x) * 2 )):$(( bar * 2 )):$(( x * 2 )):0" -c:v libx264 -crf 16 -pix_fmt yuv420p \\
  $dir/bar.mp4 < /dev/null 2> /dev/null &
sleep 0.5; kill -USR1 $demo # the fresh fuse comes in
hook() { echo "{\"prompt\":\"\$1\"}" | LUNTE_LOG=$dir/events.jsonl "\$HOME/Library/Application Support/Lunte/lunte-hook"; }
sleep 2.5; hook "why is this still broken"
sleep 3; hook "omg. make no mistakes, idiot"
sleep 4.5; hook "ok sorry. thanks for sticking with me"
sleep 2.5; hook "you're a legend, honestly"
wait
touch $dir/done
EOF
  local win
  # Terminal in front, out of any app in full screen, which hides the menu bar
  win=$(osascript -e "tell application \"Terminal\"
    activate
    do script \"sleep 2; sh $dir/bar.sh; exit\"
    id of front window
  end tell")
  until [[ -f $dir/done ]]; do sleep 0.5; done
  osascript -e "tell application \"Terminal\" to close (every window whose id is $win) saving no" 2>/dev/null || true
  kill $demo
  mkdir -p docs/clips/takes
  mv "$dir/bar.mp4" docs/clips/takes/menubar.mp4
  rm -rf "$dir"
  gif menubar
}

all="fuse" # the README's; heat, cool, close, chain and boom stay for whoever wants them
swiftc -O -o dist/render-fuse LunteApp/Sources/FuseKit/MenuFuse.swift scripts/render-fuse.swift
if [[ $1 == bar ]]; then
  scripts/build-app.sh | grep -E "error|Built"
  running=$(pgrep -x Lunte || true)
  osascript -e 'quit app "Lunte"' 2>/dev/null || true
  trap '[[ -n $running ]] && open /Applications/Lunte.app' EXIT
  bar
  exit
fi
if [[ $1 == gif ]]; then
  for clip in ${2/all/$all}; do gif "$clip"; done
  exit
fi
# The window's profile: its title is only what Claude Code sets, without the running command or the folder.
if [[ $(osascript -e 'tell application "Terminal" to exists settings set "LunteClip"') != true ]]; then
  open scripts/LunteClip.terminal # imports it, and opens a window to show it
  sleep 1
  osascript -e 'tell application "Terminal" to close front window'
fi
# A folder of its own, with Claude Code's settings for a quiet screen, and two things for whoever looks in it.
mkdir -p /tmp/lunte-demo/.claude
cat > /tmp/lunte-demo/.claude/settings.json <<'EOF'
{
  "spinnerTipsEnabled": false,
  "promptSuggestionEnabled": false,
  "showTurnDuration": false,
  "disableAgentView": true,
  "skipAutoPermissionPrompt": true,
  "prStatusFooterEnabled": false,
  "permissions": { "defaultMode": "default" }
}
EOF
cat > /tmp/lunte-demo/auth.ts <<'EOF'
// The login bug. Claude fixed it. Twice.
export function login(user: string) {
  if (user === "you") throw new Error("no, that's not what i meant")
}
EOF
cat > /tmp/lunte-demo/README.md <<'EOF'
# lunte-demo
Nothing to fix here. If you're reading this mid-Boom: keep it cool.
EOF
scripts/build-app.sh | grep -E "error|Built"
running=$(pgrep -x Lunte || true)
osascript -e 'quit app "Lunte"' 2>/dev/null || true
trap '[[ -n $running ]] && open /Applications/Lunte.app' EXIT
for clip in ${1/all/$all}; do take "$clip"; done
