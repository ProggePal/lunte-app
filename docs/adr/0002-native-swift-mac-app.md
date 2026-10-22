---
status: proposed
---
# Lunte is a native Swift Mac app, distributed outside the App Store

Lunte needs a menu bar item, notifications with action buttons, a window, sound, a way to hear from the hook, over-the-air updates, and optionally a local model. Every one of those is a first-party Apple API, so we build it in Swift (SwiftUI plus AppKit), Mac first.

The app is the brain, and a tiny `lunte-hook` binary inside the app bundle is the ears. Claude Code runs the hook for every prompt. It classifies the prompt itself, appends one line (no prompt text) to a log file the app watches, prints nothing, and exits. The prompt never leaves the hook process, and nothing is lost when the app isn't running.

## Considered options

- **Rust with Tauri.** It's strong on the model side, because ONNX Runtime and Hugging Face tokenizers are first-class in Rust, and for Windows later. Rejected for now: the menu bar, notification actions and audio routing would all go through third-party bindings, and the UI would be a web view. Revisit if Windows becomes real; the scoring core could move to a Rust library then.
- **A Python helper and scripts (the moodring prototype).** Rejected. It needs Python on every machine, and it has no updates.
- **Mac App Store.** Rejected. The sandbox blocks writing to `~/.claude`, which the Claude Code connection needs.

## Consequences

- **Distribution.** Signed with Panter AS's Developer ID (team BF4LY62Q92), notarized, and updated by Sparkle from this repo's GitHub Releases. Lunte ships as a Panter AS product. The hook lives inside the app, so one update path covers both.
- **Connecting to Claude Code** goes through Claude's own plugin command. Lunte doesn't touch `settings.json`; the stick lives in the menu bar. A Claude Code status line can come later, added only with the person's OK and a backup.
- **Permissions: notifications.** The app also opens at login, as a Login Item the person can see and remove. No Accessibility, no Full Disk Access, no microphone, no screen recording.
- **The model.** Laya runs through ONNX Runtime's Swift package as an optional download, never bundled.
- **No app, no game.** If the app isn't running, the hook does nothing. Accept it.
