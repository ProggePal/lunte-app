# Lunte

A game about how you talk to your AI, played in the Mac menu bar. Before you change anything, read:

- [docs/contract.md](docs/contract.md): exactly what Lunte does. It's the spec, so change it along with the code.
- [docs/why.md](docs/why.md): why each rule, and each part of the fuse's feel, is the way it is, and what was tried and dropped. Code that follows an entry points to it with a `// Why:` comment. Change the entry before you change the rule, and don't bring back anything an entry lists as **Tried** without saying why it would land differently now.
- [docs/adr](docs/adr): the big decisions.
- The hq repo next to this one (`../hq`): the game's design (`GAME.md`) and the research behind it (`docs/research/game-feel-and-motivation.md`).

## The fuse

The fuse in the menu bar is the app, and its feel is the product. It lives in `LunteApp/Sources/FuseKit/MenuFuse.swift`. `FuseScene` draws any moment as a pure function of time, so you can look at any frame without running the app. The screen-wide blast is in `LunteApp/Sources/Lunte/Blast.swift`.

Look before and after you change how it moves or looks:
- `scripts/render-fuse.sh` writes `dist/fuse.png`, every state and move frame by frame on a light and a dark menu bar, and `dist/fuse.gif`, a whole session. Open the PNG and look at it.
- `scripts/render-fuse.sh "Close call" Bang` writes just those moves, magnified: frame by frame to `dist/moves.png`, and at real speed to `dist/moves.gif` (open it in a browser, or with Quick Look). A wrong name lists the moves. To see a new move, add it to `FusePreviews.moves`.
- Motion too small to see in stills, such as the bang's 2-point jolt, shows in a slit-scan: one row of pixels from each GIF frame, stacked, so time runs down the image and sideways motion zigzags. For the bang, the row through the flash is `ffmpeg -i dist/moves.gif -vf "crop=200:1:152:58,scale=800:8:flags=neighbor,tile=1x50" -frames:v 1 dist/slit.png`. Render it with the change and without, and compare.
- In Xcode, open `LunteApp/Package.swift`, pick the `FuseKit` scheme and open `MenuFuse.swift` for the same previews and a live playground. The script needs no Xcode. Xcode's own preview-export tool didn't answer when the fuse was built.
- The renders can't show the screen-wide blast or the dim. To see those, run `scripts/build-app.sh`, then `open dist/Lunte.app --args -FuseDemo YES`. It loops a session on the real menu bar, with the screen show and without the sound.

## The popover

The popover and its windows live in `LunteApp/Sources/Lunte` (`Popover.swift`, `Sessions.swift` for Today and a session's story and chart, `Club.swift`). A finished session's name, arc and cool stretches come from `Story` in LunteCore, so they're tested there.
- `scripts/render-popover.sh` draws every state in `Previews.swift`, light and dark, to `dist/popover/`, with contact sheets. `scripts/render-popover.sh 9b pill-lab` draws just the states whose names start with those, which is much quicker. `9b-opened` is a session opened under its row. Add a fixture there to see a new state.
- The `see-lunte` skill (`.claude/skills/see-lunte`) covers the rest: the real panel with real data, installing a build, and matching system colours.

## Checks

```bash
swift test --package-path LunteCore
```

```bash
swift test --package-path LunteApp
```
