# Prototype 1 contract

The shared contract between the pieces. Builders code against this; change it here first.

## Layout

```
app/
  LunteCore/    Swift package: LunteCore (logic), lunte-hook (the Claude Code hook), tests
  LunteApp/     Swift package: Lunte (the menu bar app), depends on ../LunteCore and Sparkle
  relay/        Cloudflare Worker + one Durable Object per Club
  plugin/       Claude Code plugin + marketplace, bundled into the app
  Resources/    boom.wav, Info.plist
  scripts/      build-app.sh
```

## 1. The event log

`~/Library/Application Support/Lunte/events.jsonl`. The `LUNTE_LOG` environment variable overrides the path, for tests and development. `lunte-hook` appends one line per prompt. The only other writer is the app, which appends a `rest` line when a hurried break ends (§6). It never holds prompt text.

```json
{"v":1,"ts":1792670480.123,"burn":"none","sid":"<Claude Code session_id>"}
```

- `burn`: `"none"`, `"tell"` (telling it off), `"lose"` (losing it) or `"test"` (the onboarding phrase, §6). `"rest"` is written by the app, never by the hook.
- `ts`: Unix seconds, as a Double.
- `sid`: the Claude Code session id, kept as a pointer for a later `lunte why`. It may be `""`.
- **Writers** append one whole line with a single `write()` under `O_APPEND`.
- **Readers** skip lines they can't parse, drop events whose `ts` isn't finite or lies outside `0 < ts < 1e11`, and sort by `ts`.

## 2. The hook

`lunte-hook` reads Claude Code's `UserPromptSubmit` JSON from stdin (`{"prompt": "...", "session_id": "...", ...}`). It classifies the prompt, appends one log line, prints nothing, and exits 0, always, even on errors. It creates the directory if missing and finishes in well under 100 ms.

The plugin lives at `Lunte.app/Contents/Resources/plugin`. Claude Code runs a cached copy of it (`~/.claude/plugins/cache/...`), so the hook can't reach the app by a relative path. Instead the app keeps a link at `~/Library/Application Support/Lunte/lunte-hook` pointing to its own `Contents/MacOS/lunte-hook`, refreshed on every launch, and the hook command is `"$HOME/Library/Application Support/Lunte/lunte-hook"`.

## 3. Classifier: `Classifier.classify(_:) -> Burn`

Strip ```` ``` ```` fenced blocks, then match case-insensitively on Unicode word boundaries.

- **test** beats everything: `3 2 1 pow`, with any spaces or punctuation between (`3, 2, 1… POW!`, `321 pow`). It's the onboarding phrase.

- **lose** (losing it), which beats tell:
  - a swear: `fuck*, shit*, bitch*, damn*, crap*, asshole*, bastard*, dick, piss*, bollocks, wtf, ffs, omfg, hell, faen*, helvete, hælvete, jævl*, dritt*, satan, kuk, pikk`
  - three CAPS words in a row
  - `!!`, `?!` or `!?`
  - `useless`, `stupid`, `are you kidding`, `what the hell`, `herregud`, `seriøst`
- **tell** (telling it off): `i said`, `i told you`, `i already said`, `i asked you`, `why did you`, `why would you`, `why are you`, `you (just) broke|deleted|ignored|removed`, `not what i asked|said|wanted`, `that's wrong`, `that's not it`, `stop it|that|doing`, `come on`, `seriously`, `ugh`, `argh`, `jeg sa`, `jeg har sagt`, `hvorfor gjorde du`, `hvorfor gjør du`, `du slettet`, `du ødela`, `kom igjen`
- **Happy guard:** if the prompt has a happy word, swears, CAPS and `!!` don't count, though the other phrases still do. The happy words are `awesome, amazing, love, perfect, great, nice, cool, sick, wow, insane, let's go, yay, hell yeah, thanks, thank you, thx, appreciate, legend, bra, digg, rått, takk, nydelig, herlig`.
- **none:** everything else, including bug reports ("broken", "not working", "still failing", "funker ikke") and a plain "no".

These cases must pass:

| Prompt | Burn |
|---|---|
| `this is still broken` | none |
| `still broken wtf` | lose |
| `fucking awesome, thanks!` | none |
| `faen så bra` | none |
| `tusen takk faen` | none |
| `faen, det funker ikke` | lose |
| `I SAID DONT TOUCH IT` | lose |
| `no, why did you delete the tests` | tell |
| `no, use the other table` | none |
| `hvorfor gjorde du det?!` | lose |
| `jeg sa ikke det` | tell |
| ```` fix it:\n```\nError: build broken, wtf\n``` ```` | none |
| `amazing!!` | none |
| `rename foo to bar` | none |
| `hello shell` | none |
| `what the hell are you doing` | lose |
| `come on` | tell |

## 4. The game: `Game.replay(_:now:) -> GameState`

Pure and deterministic, over the whole log.

- **Sitting:** consecutive events less than 10 minutes (600 s) apart. A gap of 600 s or more (a break) starts a new Sitting.
- **Fuse** starts at 2 (`minFuse`). Every Sitting starts a fresh stick with `pieces = fuse`.
- **`.test` events** count as activity for Sittings but never burn, never Boom and never change the fuse.
- **`.rest` events** close the open Sitting on the spot, exactly like a break. The next prompt then starts a fresh Sitting, without counting the empty stretch in between as a calm Sitting.
- **Each Burn**, in a Sitting that hasn't Boomed yet. Telling it off burns one piece; losing it burns two.
  - `.lose` and `pieces <= 2`: **Boom** (`pieces = 0`, `fuse += 1`)
  - `.lose` otherwise: `pieces -= 2`
  - `.tell`: `pieces = max(1, pieces - 1)`, so it never takes the last piece and stays on the spark
- **After a Boom,** the Sitting can't Boom again.
- **A Sitting that ends without a Boom** sets `fuse = max(2, fuse - 1)`. A Sitting ends when the next event is 600 s or more later, or, for the current state, when `now - lastEvent >= 600`.
- **`Boom`** is `{id, ts, litBy}`. `id = String(Int(ts * 1000))`, so it stays stable across replays. `litBy` holds that Sitting's Burns up to and including the Boom.
- **`GameState`** is `{fuse, pieces, boomed, sittingOpen, currentBurns, booms}`. With no open Sitting, `pieces == fuse` and `boomed == false`.
- **`Game.stickText`:**
  - when boomed: `💥`
  - otherwise `🧨` followed by pieces: `🧨━━━` (3), `🧨━━` (2), `🧨✨` (1)
- **`Game.litByText`:** `10:12 told off · 14:40 lost it`, in local time.
- **`Classifier.signals(_:)`:** the reasons behind a classification, for display only, such as `["told off: why did you", "swear", "CAPS"]`.
- **`Transcript.prompt(sid:ts:)`:** the prompt text for an event, read from Claude Code's own transcript (`~/.claude/projects/*/<sid>.jsonl`, the human prompt within 5 s of `ts`). It's used for display only and never stored. Claude Code deletes old transcripts, so it can come back nil.

Fixtures that must pass:
1. One `lose` on a fresh stick (fuse 2): a Boom, then fuse 3.
2. `tell`, `tell`: no Boom, pieces 1.
3. `tell`, `lose`: a Boom.
4. More `lose` after a Boom in the same Sitting: still one Boom.
5. After a Boom (fuse 3), a calm Sitting followed by a gap: fuse 2, and never below 2.
6. A gap of 599 s is the same Sitting; a gap of 600 s is a new one.
9. With fuse 4: a `lose` leaves 2, a `tell` leaves 1, and the next `lose` Booms.
7. Last event 11 minutes before `now`: `sittingOpen == false`, `pieces == fuse`.
8. Replaying twice gives the same Boom ids.

## 5. The relay (HTTP + JSON)

Base URL comes from Info.plist `LunteRelayURL`, overridable with `defaults write no.panter.lunte RelayURL http://localhost:8787`. Bodies are at most 2 KB. Errors: 400 for bad input, 401 for a bad token, 403 for a `why` whose secret doesn't match, 404 for an unknown Club or Boom, 409 for a Boom id or name already taken, 413 for a body that's too big, 429 for too many joins. A request to a Club that doesn't exist never creates storage.

- `POST /clubs {"name":"Night Shift"}` → `201 {"club":"K7M2QX","name":"Night Shift"}`: a 6-character code from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`. The name follows the member-name rules (1–24 characters, no category C). It's optional and defaults to the code.
- `POST /clubs/{club}/join {"name":"Paal"}` → `200 {"member":"<id>","token":"<secret>","clubName":"Night Shift"}`.
  - The name is 1–24 characters after trimming, with no control or invisible characters (Unicode category C).
  - Names are unique per Club, compared after NFKC normalisation and lowercasing (409 if taken).
  - A Club has at most 50 members and accepts at most 10 joins an hour (429).
  - Every join posts `{"type":"join","from":"<name>"}` to the feed, so nobody joins unnoticed.
  - Tokens are stored hashed.
- `POST /clubs/{club}/events` with `Authorization: Bearer <token>` → `201 {"seq":n}`:
  - `{"type":"boom","boom":"<id>","ts":<s>,"proof":"<sha256 hex of a local secret>"}`. Stored **without** the member, because Booms are anonymous. Boom ids are unique per Club (409 on a repeat), and Booms with their proofs live in their own table that is never trimmed.
  - `{"type":"react","boom":"<id>","emoji":"🧯"}`: a single grapheme, at most 16 bytes. Stored with `from` set to the member's name.
  - `{"type":"why","boom":"<id>","text":"...","secret":"<local secret>"}`: 1–140 characters. Accepted only if `sha256(secret)` matches the Boom's proof, so you can only explain your own Boom: 404 if the Boom is unknown, 403 if the secret doesn't match. Stored with `from` set to the member's name. The proof and the secret are never returned.
- `GET /clubs/{club}/events?after=<seq>` (Bearer) → `200 {"events":[...]}`: oldest first, at most 100 per call, and only the last 500 kept. Each event is `{seq, type, boom?, ts, emoji?, text?, from?}`, where `type` is `boom`, `react`, `why` or `join`. Boom events never carry `from`.

## 6. The app (`Lunte.app`)

**Basics.** A menu bar-only app (`LSUIElement`) with bundle id `no.panter.lunte`, for macOS 14 and later. The menu bar label is `Game.stickText(state)`.

**Watching the log.** It watches `events.jsonl` with a file-system source and a 1 s debounce, reopening the file if it's created or replaced. On every change it replays the log. For a new Boom:
- **Not yet announced and less than 10 minutes old:** play `boom.wav` (unless the sound is off) and post it to the relay if you're in a Club.
- **Older:** mark it announced silently.

The app keeps each Boom's secret and its "mine" flag in UserDefaults.

**Onboarding: the first Boom.**
- Until the log holds a `test` event, the menu's status line reads "Not connected yet: open a new Claude Code chat and type: this is a test 3 2 1 pow".
- After "Connect to Claude Code" succeeds, the alert says the same: open a *new* chat, because Claude Code loads plugins when a session starts.
- A new `test` event (less than 10 minutes old, not yet announced) plays the Boom and shows "💥 We're connected! Lunte hears you. Ready." It is never posted to the Club.

**The popover** replaces a menu:
- **Before the first Boom:** the onboarding checklist.
- **The stick** as segments, with one plain sentence. Hovering it shows the break countdown: "Step away 8:41 for a fresh stick". Any prompt restarts the 10 minutes.
- **The Boom card:**
  - "💥 Boom 3 minutes ago", live
  - the prompt that set it off, on one line, truncated with "…"
  - your Club's reactions
  - a live countdown, "Fresh stick in 8:41"
  - **Easter egg, with no UI:** once you've justified, each tap on the 💥 shaves 2 s off the break, at most 60 s. When a hurried countdown reaches zero, the app appends a `rest` event and the stick is fresh. A new prompt restarts the break and resets the shave.
  - tapping the 💥 opens the Justify field, at most 40 characters
- **Your last 10 messages** as dots. Hovering one shows a detail line: time, kind, signals and the prompt text (one line, truncated).
- **The footer:** sound on the left; the Club in the centre (a house icon and its name, or "No Club"), with the Club actions behind it; a gear on the right for the rest.

**The old menu (superseded by the popover):**
- a status line: `Fuse 3 · 2 left`, or `💥 lit by 10:12 told off · 14:40 lost it`
- "Justify", a one-line field on the Boom card for your own Boom when you're in a Club (sent as a `why` event)
- the Club: "Create a Club" (shows the code to share) and "Join a Club…" (code and name), or, once you're in one, the Club code plus its last 5 events
- "Test your Boom"
- a sound on/off toggle
- "Connect to Claude Code", which runs `claude plugin marketplace add <bundle>/Contents/Resources/plugin` and then `claude plugin install lunte@lunte`, finding `claude` through a login shell
- "Feedback & ideas…", which opens `https://github.com/ProggePal/lunte-app/issues/new`
- "Check for Updates…", through Sparkle
- "Quit"

**The Club.** The app polls every 30 s.
- **Someone else's Boom:** a notification "💥 Boom in your Club" with 🧯 😂 🫂 actions, each of which posts a react.
- **A react on your own Boom, a why on someone else's, or a join:** a notification such as "🧯 from Ola", "Paal: …" or "Ola joined your Club".
- **Catching up after being offline:** events older than 10 minutes go into the feed without a notification.
- **A Boom counts as yours** only once the relay has accepted it (201). Leaving a Club forgets your Booms and their secrets.
- **Run from Downloads:** if macOS runs the app from a temporary path (App Translocation), the app asks to be moved to Applications and doesn't link the hook.

**Sparkle.** `SUFeedURL` is `https://github.com/ProggePal/lunte-app/releases/latest/download/appcast.xml`. `SUPublicEDKey` gets set at release time, and the updater stays off while it's empty.

## 7. Build

`scripts/build-app.sh [--release]` builds both packages and assembles `dist/Lunte.app`:
- `Contents/MacOS/{Lunte,lunte-hook}`
- `Contents/Frameworks/Sparkle.framework`
- `Contents/Resources/{boom.wav,plugin/}`
- `Contents/Info.plist`

A dev build is signed ad-hoc. `--release` signs with `Developer ID Application: Panter AS (BF4LY62Q92)` and the hardened runtime. Notarizing and the appcast are a separate release step.
