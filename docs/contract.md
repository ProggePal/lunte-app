# Prototype 1 contract

The shared contract between the pieces. Builders code against this; change it here first.

## Layout

```
app/
  LunteCore/    Swift package: LunteCore (logic), lunte-hook (the Claude Code hook), tests
  LunteApp/     Swift package: Lunte (the menu bar app), depends on ../LunteCore, Sparkle, LayaKit (vendored) and FuseKit (the menu bar fuse)
  relay/        Cloudflare Worker + one Durable Object per Club
  plugin/       Claude Code plugin + marketplace, bundled into the app
  Resources/    boom.wav, Info.plist, Lunte.icns
  scripts/      build-app.sh, render-fuse.sh
```

## 1. The event log

`~/Library/Application Support/Lunte/events.jsonl`. The `LUNTE_LOG` environment variable overrides the path, for tests and development. `lunte-hook` appends one line per prompt. The only other writer is the app, which appends a `heat` line when its model has rated a prompt and a `rest` line when a hurried break ends (§6). It never holds prompt text.

```json
{"v":1,"ts":1792670480.123,"burn":"none","sid":"<Claude Code session_id>","rated":true}
{"v":1,"ts":1792670480.123,"burn":"heat","sid":"","heat":0.93,"cool":0.05,"mood":"frustrated","topic":"code"}
```

- `burn`: `"none"`, `"tell"` (telling it off), `"lose"` (losing it) or `"test"` (the onboarding phrase, §6). `"heat"` and `"rest"` are written by the app, never by the hook.
- `rated`: present and `true` when the hook handed the prompt to the app's model (§2), so a `heat` line should follow.
- `heat` lines: the model's ratings, `heat` 0…1 and `cool` 0…1 (§8; absent without a cool model and in older logs), its `mood` choice, and the message's `topic`: one word from `Vibe.topics` (code, design, writing, business, voice, shipping, ideas, other), never text. Readers merge one into the prompt line with the same `ts` and drop it; a heat line without its prompt is dropped.
- `ts`: Unix seconds, as a Double.
- `sid`: the Claude Code session id, kept as a pointer for a later `lunte why`. It may be `""`.
- **Writers** append one whole line with a single `write()` under `O_APPEND`.
- **Readers** skip lines they can't parse, drop events whose `ts` isn't finite or lies outside `0 < ts < 1e11`, and sort by `ts`.

## 2. The hook

`lunte-hook` reads Claude Code's `UserPromptSubmit` JSON from stdin (`{"prompt": "...", "session_id": "...", ...}`). Claude Code also submits machine messages as prompts: subagent hand-backs (`Another Claude session sent a message:` + `<agent-message>`), `<task-notification>`, `<system-reminder>` and `<local-command-…>` blocks, sometimes glued to a message typed mid-turn. `Classifier.human(_:)` cuts those blocks out (an unclosed one runs to the end); if nothing is left, the hook logs nothing. It classifies what's left, hands it to the app's model (below), appends one log line, prints nothing, and exits 0, always, even on errors. It creates the directory if missing and finishes in well under 100 ms.

The plugin lives at `Lunte.app/Contents/Resources/plugin`. Claude Code runs a cached copy of it (`~/.claude/plugins/cache/...`), so the hook can't reach the app by a relative path. Instead the app keeps a link at `~/Library/Application Support/Lunte/lunte-hook` pointing to its own `Contents/MacOS/lunte-hook`, refreshed on every launch, and the hook command is `"$HOME/Library/Application Support/Lunte/lunte-hook"`.

**Commands for fuse setup** (§8). With an argument, `lunte-hook` is a tool for your AI, not the hook, so it may print:
- `lunte-hook setup` prints the steps for your AI (§8).
- `lunte-hook messages` prints the messages to rate, one JSON line each: `{"sid", "ts", "text"}`, with `ts` in seconds to the millisecond and the text cut at 300 characters. That's `Fuse.candidates` over `Transcript.all` for the last 60 days, about 20 s on 2 GB of history.
- `lunte-hook check-fuse` validates `fuse/labels.json` and checks that every rating points at a message it can find. It prints "OK: …" and exits 0, or lists the problems and exits 1.

**Handing a prompt to the model.** `ScorerSocket.send` connects to the Unix socket `scorer.sock` next to the log, without blocking, and writes one JSON line `{"ts", "text"}` (at most 4,000 characters). It succeeds only if the app is listening; then the hook logs `rated: true`. The text goes over the socket only, never to disk.

## 3. Classifier: `Classifier.classify(_:) -> Burn`

Strip ```` ``` ```` fenced blocks, then match case-insensitively on Unicode word boundaries.

- **test** beats everything: `3 2 1 boom`, with any spaces or punctuation between (`3, 2, 1… BOOM!`, `321 boom`). It's the onboarding phrase. `3 2 1 pow`, as it used to be, still counts.

- **lose** (losing it), which beats tell:
  - a swear: `fuck*, shit*, bitch*, damn*, crap*, asshole*, bastard*, dick, piss*, bollocks, wtf, ffs, omfg, hell, faen*, helvete, hælvete, jævl*, dritt*, satan, kuk, pikk`
  - `useless`, `stupid`, `are you kidding`, `what the hell`, `herregud`, `seriøst`
  - a telling-off (below) turned up with three CAPS words in a row, or with `!!`, `?!` or `!?`
- **tell** (telling it off): `i said`, `i told you`, `i already said`, `i asked you`, `why did you`, `why would you`, `why are you`, `you (just) broke|deleted|ignored|removed`, `not what i asked|said|wanted`, `that's wrong`, `that's not it`, `stop it|that|doing`, `come on`, `seriously`, `ugh`, `argh`, `jeg sa`, `jeg har sagt`, `hvorfor gjorde du`, `hvorfor gjør du`, `du slettet`, `du ødela`, `kom igjen`
- **Volume alone is none:** CAPS and `!!` on their own, or together, don't burn. Heat is anger, not volume ([why](why.md#heat-not-volume)).
- **Happy guard:** if the prompt has a happy word, swears don't count, and CAPS and `!!` don't turn a telling-off up, though the other phrases still do. The happy words are `awesome, amazing, love, perfect, great, nice, cool, sick, wow, insane, let's go, yay, hell yeah, thanks, thank you, thx, appreciate, legend, bra, digg, rått, takk, nydelig, herlig`.
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
| `it's still broken!!` | none |
| `WHY IS IT STILL BROKEN` | none |

## 4. The game: `Game.replay(_:now:timeZone:) -> GameState`

Pure and deterministic, over the whole log. `timeZone` (default `.current`) sets the local calendar days the fuse counts. The app replays in the Mac's current time zone, so travelling can move a past session's day, and with it the calm workdays and the cool point. Why each rule is there, with its evidence and a source, is in [why.md](why.md); the code links each rule to its entry with a `// Why:` comment.

Every message has **heat** and **cool**, each 0…1. Heat burns heat² of the fuse and cool mends some of it back, so calm messages barely touch it and hot ones eat it. A burn cools off after 30 minutes. Too much heat at once and it blows: once per Sitting, and more heat soon after escalates the same Boom.

- **Heat** (`Event.heat(at: now)`): the model's rating from the merged `heat` line. Heat is anger, not volume. Without one, the word list: `tell` 0.6, `lose` 1, anything else 0. A `rated` prompt still waiting for its rating counts as 0 for `ratingWait` (90 s), so the word list can't Boom before the model speaks; after that the word list decides.
- **Cool** (`Event.cool`): the model's cool from the same `heat` line (§8): talking to your agent like a best bud. Nil without a cool model and in older logs, and nil counts as 0. A message counts as cool from `coolPrompt` (1/3, your AI's 1 of 3).
- **Burn** (`Game.burn(_:at:)`): heat² less `coolMend` (0.5) × cool² (`Game.mend`), where either part below 0.01 counts as 0. So a cool message is negative, and a hot and cool one ("you absolute clown 😂") burns less than the heat alone.
- **Sitting** (a session in GAME.md): it starts with a message and closes after 30 minutes (`sittingGap`, 1800 s) without one. It has no length cap. The next message after that starts a new Sitting with a fresh stick.
- **Fuse** is how much heat² the stick takes: 1 (`minFuse`) to start, +0.75 per Boom (`boomGrowth`), −0.25 per calm workday (`calmWorkdayShrink`), never below 1 ([why](why.md#rare-booms)).
  - A **calm workday** is a local calendar day with at least one prompt and no Boom. `.test` prompts don't make a workday. It shrinks the fuse once it's over, at the first prompt after midnight or at `now`; a day without prompts changes nothing.
  - A Sitting keeps the stick it started with, even past midnight; the shorter stick comes with the next Sitting.
- **Burning:** a message whose burn isn't 0 joins what's burning, and `burned` adds each one's burn in turn, never going below 0, so cool can't be banked before the heat. Only messages from the last 30 minutes (`cooling`) count; each drops out when its 30 minutes are up. The messages with heat² of 0.01 or more are the Sitting's `currentBurns`.
- **Boom:** when `burned >= fuse` in a Sitting that hasn't Boomed. `fuse += 0.75`, and `fuse` shows the next stick from then on. A Sitting Booms once and stays blown until it closes.
- **Tiers:** after the Boom the burn starts again from 0, and each further half of the stick that blew (`escalationStep`, 0.5) within 30 minutes of the Boom (`escalationWindow`, 1800 s) steps the same Boom up a tier: 1 Boom, 2 Chain reaction at +½ stick, 3 Meltdown at +1 stick (`maxTier`; names and emoji in `Game.tiers`) ([why](why.md#tiers-flavour-not-volume)). Each step's time goes in `Boom.escalations`; a prompt that steps up two tiers is there twice. After 30 minutes nothing escalates, though the Sitting stays blown until it closes. It's still one Boom, with the same id, and more heat at Meltdown changes nothing.
- **Fresh stick after a Boom:** only when the Sitting closes. `freshAt` is the last message + 30 minutes.
- **Close call:** the stick gets into its last third (`Game.inLastThird(left)`: `left <= 1/3`, `closeCallLeft`, with 1e-9 of float slack, so a heat-1 burn on a 1.5 stick counts) and climbs back out without a Boom in between, because a cool message mended it or the burn that put it there cooled off. Cooling is timed when the burn's 30 minutes are up, also after the last message, so walking away from a dip counts. `CloseCall` is `{ts, cooled}`: when it dipped and when it climbed out. One per dip; a dip that Booms, or that a `rest` cuts short, is none.
- **`.test` events** count as messages for Sittings but never burn, never Boom and never change the fuse.
- **`.rest` events** close the open Sitting on the spot, and the next prompt starts a fresh Sitting. A rest isn't a prompt, so it doesn't make a workday.
- **`Boom`** is `{id, ts, litBy, escalations}` with `tier` (1–3). `id = String(Int(ts * 1000))`, so it stays stable across replays. `litBy` holds the burns still burning when it blew, up to and including the Boom.
- **`Sitting`** is `{start, end, prompts, peakHeat, coolPrompts, boom, closeCalls, lastBurn, isOpen, aura}`, with `tier` (0 without a Boom) and `cooledOff`. `aura` is its one award, set by the replay (below). `end` is its last message. `coolPrompts` counts messages with cool of at least `coolPrompt`. `cooledOff` is when the last burn had cooled off (`lastBurn` + 30 minutes), if you were still at it then. Sittings are facts about your day and stay on your Mac.
- **`GameState`** is `{fuse, burned, boomed, sittingOpen, currentBurns, booms, sittingStart, freshAt, sittings}`. `left` is the share of stick left (0 when blown), `sitting` the open Sitting, and `closeCalls` every close call. `sittings` holds every Sitting, oldest first: the closed ones, then the open one. After a Boom, `burned` counts toward the tiers. With no open Sitting, `burned == 0` and `boomed == false`.
- **`Game.sessionLine(_:)`:** one line about a Sitting, built from what happened, never a guess at your mood. It ends on the recovery when there is one (the peak-end rule). Four templates:
  - no Boom and no close call: "Cool all the way. 42 prompts."
  - close calls: "Close call at 14:12. Cooled off." or "3 close calls, the last at 15:03. Cooled off."
  - a Boom: "Boomed at 14:12.", with "Slow burn. " in front when its burns built up over 10 minutes or more (`slowBurn`)
  - an escalated Boom, by its top tier: "Chain reaction at 15:03." or "Meltdown at 15:20."

  A Boom line ends with "Cooled off by 14:40." when `cooledOff` is set.
- **Aura** (`Game.aura(_:)`, which returns `Sitting.aura`): one award per Sitting, the best thing that happened, without roasts ([why](why.md#aura-not-work)).
  - A Sitting with any close call earns `closeCallAura` (3), at once, and keeps it if a Boom comes after.
  - Otherwise a cool Sitting, `coolSittingPrompts` (5) or more messages and no Boom, earns `coolSittingAura` (1) when it closes, but only the first one on the local day it started. So an open Sitting's cool point waits for the close, and aura never goes down.
  - Otherwise 0.
  - A roast is worth `roastAura` (8). The Club's reactions decide roasts, in the app and the relay, not the replay. A roasted Sitting's one award is the roast, in place of its `aura`.
- **`Game.stickText`:** `💥` when blown, otherwise `🧨` plus one `━` per third left, or `🧨✨` in the last third (`Game.inLastThird`).
- **`Game.heatWord`:** cool (< 0.15), mild (< 0.35), warm (< 0.6), hot (< 0.85), boiling.
- **The vibe** (`Vibe`): one dry line about the last 30 minutes, never sent. Parked: the popover doesn't show it (GAME.md parks live vibe words), and it stays off unless it was switched on before.
  - A vibe has an emoji, a label, a band (calm, warm, hot, explosive), a short `when` and a one-line story for hover.
  - `Vibe.stock` ships with the app, and updates can rotate new ones in. Your AI can add personal ones at fuse setup (§8).
  - **No vibe** until there are 5 messages (`Vibe.minimumMessages`) in the window: "Reading the room…".
  - **Band** (`Vibe.band`): explosive when blown; hot at half the fuse or less; warm with any message at heat 0.35 or more; calm otherwise.
  - **Topic** (`Vibe.topic`): the topic of at least 3 messages and 40% of those with one in the window, ignoring "other"; else none.
  - **Shortlist** (`Vibe.candidates`): up to 6 vibes from the band. Up to 3 of yours come first, then stock, with no repeated labels. A vibe of yours that's about a topic only makes the list when the session is about that topic, and then it goes first. It rotates by half hour, so the same moment gets the same shortlist.
  - **Pick:** Laya chooses by label from a text-free summary (`Vibe.summary`): message count, recent heat words, top moods, top topics, fuse left, a recent Boom, weekday and time. Six labels take 38 of the 128 tokens, so the summary fits whole. Without the model, the old rules (`Vibe.of`) pick from the stock vibes.
  - **When it changes:** only when the band changes or after 3 new messages, so it moves with the session without flickering.
  - **New vibes:** the first time a vibe ever shows, it gets "✨ new". There's no counter and no list, so vibes are found by playing.
- **`Classifier.signals(_:)`:** the reasons behind a classification, for display only, such as `["told off: why did you", "swear", "CAPS"]`.
- **`Transcript.prompt(sid:ts:)`:** the prompt text for an event, read from Claude Code's own transcript (`~/.claude/projects/*/<sid>.jsonl`, the human prompt within 5 s of `ts`). It's used for display only and never stored. Claude Code deletes old transcripts, so it can come back nil.

Fixtures that must pass (GameTests, SittingTests):
1. One `lose` on a fresh stick: a Boom, then fuse 1.75.
2. `tell`, `tell`: no Boom, 0.72 burned.
3. `tell`, `lose` Booms, and so do three `tell`s.
4. More heat after a Boom: still one Boom.
5. The thermostat: a calm workday shortens the fuse by 0.25, never below 1. A calm Sitting, a day that Boomed, a day without prompts, a day with only `.test` and a day with only a rest don't; a Sitting keeps its stick past midnight; a 25-hour day across a DST change shrinks it once.
6. A gap of 1,799 s is the same Sitting; a gap of 1,800 s closes it. A message every 20 minutes for 5 hours is one Sitting.
7. Last event 31 minutes before `now`: `sittingOpen == false`, the whole stick left.
8. Replaying twice gives the same Boom ids.
9. A burn cools off after 30 minutes, so the third `tell` doesn't Boom when the first has cooled.
10. Blown until the Sitting closes, however long ago the burn cooled; the fuse keeps its growth.
11. The model's heat beats the word list both ways.
12. A rated prompt waits for its rating, then the word list decides.
13. `freshAt` is the last message + 30 minutes, and only after a Boom.
14. Cool mends the fuse, never below 0, and can't be banked; a hot and cool message burns less than the heat alone.
15. One Boom per Sitting: the burn starts again from 0, and each further half of the stick that blew steps up to Chain reaction and Meltdown, then stops; a whole stick at once steps up two; nothing escalates 30 minutes or more after the Boom.
16. Close calls: mended by cool, cooled off, or walked away from; none when it Booms or a rest cuts the dip short; one per dip; and one at exactly a third left.
17. Sitting summaries: start, end, prompts, peak heat, cool prompts, the Boom, open or closed.
18. Each session line template, its variants and the recovery.
19. Aura: one award per Sitting (a close call 3, a cool Sitting 1, never both), a cool point at most once per local day, an open Sitting, and a Boom.

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
- `POST /prompts {"name", "prompt", "version"}` → `201 {"id": n}`: an idea for Lunte, from Submit a prompt. No account needed.
  - The prompt is 1–4,000 characters, and the name is optional, at most 40 visible characters. Bodies here can be up to 16 KB.
  - Each sender gets 10 an hour, and the inbox takes 500 a day in all (429).
  - The sender is a hash of their IP, kept a day for the limit and never stored with the prompt.
- `GET /prompts` with `Authorization: Bearer <ADMIN_TOKEN>` → `200 {"prompts": [{id, ts, name, prompt, version}]}`, newest first, at most 500; 401 otherwise.
  - The token is a Worker secret (`wrangler secret put ADMIN_TOKEN`), `dev-admin` in `relay/.dev.vars` locally.
  - On the release Mac it's in the keychain as `lunte-admin`, and `npm run prompts` in `relay/` reads the inbox with it.
- `GET /clubs/{club}/events?after=<seq>` (Bearer) → `200 {"events":[...]}`: oldest first, at most 100 per call, and only the last 500 kept. Each event is `{seq, type, boom?, ts, emoji?, text?, from?}`, where `type` is `boom`, `react`, `why` or `join`. Boom events never carry `from`.

## 6. The app (`Lunte.app`)

**Basics.** A menu bar-only app (`LSUIElement`) with bundle id `no.panter.lunte`, for macOS 14 and later. The menu bar item is the fuse, drawn live by `FuseKit` over its own status item (`FuseScene` draws any moment as a pure function of time; `FuseView` draws on a display link only while something moves):
- **The fuse:** a coil of three loops, fixed at its start on the left, a little uneven, like a spring: the more fuse is left, the tighter the coils; the less, the wider they spread. It moves only when a prompt does something, and is still in between.
- **A prompt:** while the model rates it (`Event.awaitingRating`), a faint breeze ripples through the coils. Then one of four things happens. Nothing: the breeze dies down. Heat: the tip catches and burns its bite away, right to left (heat² over the stick): the flame flares and runs back, sparks fly, the burnt bit glows and falls as ash, and what's left springs apart. In the last third it crawls instead: it creeps, nearly stops, gutters and creeps on (`Ease.hesitate`), so you can't tell if it'll stop in time. The flame burns on for 2.5 s, 3.5 s past half, or 5 s in the last third (`FuseScene.flameFor`), amber, orange or red and trembling, then goes out in a puff. Cool: new fuse feeds in at the start, left to right, green with twinkles, squeezing the coils together. Both: the two at once, the start growing by the rest of the change. While a burn crawls through the last third the screen dims a little, deeper the nearer the end, until the flame goes out or the fuse grows back: a close call starts just like a Boom. Climbing out of the last third flashes green.
- **Burnt through**, the Boom's own burn starts slow and races faster and faster to the end in 1.6 s (`FuseScene.raceFor`), the flame dies at the start in a puff, and then there's silence.
- **The bang** lands in the stillness, and time eases back up from a near stop over 0.9 s (`FuseScene.speedUp`) as it opens out: a flash, a shockwave, a spray of sparks, puffs of smoke and a jolt where the fuse began. Once the smoke has cleared, 1.6 s after the bang (`FuseScene.calmAfter`), the plain word lands with a bounce.
- **Blown and calm**, there's no fire: an SF Symbol and a word in the menu bar's own colour and font, still unless they change. First `burst.fill` and the tier's name (Boom, Chain reaction, Meltdown), for at least 5 s (`FuseScene.nameFor`). Then `flame.fill` "Still burning" while the heat toward the next tier is a quarter of the way or more, and `wind` "Calmed down" once it's quiet (10 minutes after the Boom or its last escalation), dimmed a little. Otherwise the tier's name. A change swaps them quietly: the old one rises away, the new one springs up from below, and a new tier gives the symbol a small pop. The item widens for the longest of them and stays that wide until the session ends, so the menu bar doesn't jitter.
- **A new session** feeds in a fresh fuse from the left.
- **Before it's connected** the coil is faint. With Reduce Motion every change snaps. Its tooltip and VoiceOver label say how much fuse is left, or the tier.

**Watching the log.** It watches `events.jsonl` with a file-system source and a 1 s debounce, reopening the file if it's created or replaced. On every change it replays the log. For a new Boom:
- **Not yet announced and less than 10 minutes old:** light the fuse: it races down in 1.6 s, then a random 1–6 s of silence (`GameModel.silence`), so the room has to guess who it was. As the fuse races through its last third the screen dims, plain black, darker at the edges and under the menu bar so the fuse stays bright, all the way dark once it's through (`FuseScene.dark`), and it stays dark through the silence; unless the sound is off, a soft fizz (0.4 s of synthesised noise) starts just before the bang. Then it blows from the fuse's own spot on screen, starting from a near stop and easing back up to speed (`Blast.speed`): a flash of the whole screen, a bloom of light, two shockwaves, wisps of smoke, sparks and embers, as the light comes back over 2.4 s (native Core Animation in a click-through overlay) and plays `boom.wav` right after the fizz, both capped at 0.6 of the Mac's volume. At that moment, sound or not, it posts the Boom to the relay if you're in a Club, so no Club Mac hears of it before the bang. If the Mac slept through the wait (more than 2 s late by the wall clock, `Blast.lateBy`), there's no dim, sound, burst or post; the Boom stays in the log and on its card. With Reduce Motion there's only the wait and the sound. The onboarding test burns for 3 s.
- **Older:** mark it announced silently.

A Boom counts as announced at its bang, or when the Mac slept through it. So one whose fuse is still burning when Lunte quits, crashes or updates lights again, with a new wait, when it opens, if it's still under 10 minutes old.

A Sitting bangs once. A late rating, or a word-list decision after `ratingWait`, can move a Sitting's Boom to an earlier prompt, which gives it a new id; a Boom whose Sitting has been lit already is marked announced silently. The app keeps the lit Sittings by start, with the id each was lit for, in UserDefaults (`Lit`, next to `Announced`), and the Boom's comment and reactions stay with that id.

The app keeps each Boom's secret and its "mine" flag in UserDefaults.

**The model.** `Scorer` rates prompts with Laya on the Neural Engine, untuned for now: heat is its P(frustrated) for one short mood question, "The writer's mood toward their AI assistant?", with six options (frustrated, confused, hyped, grateful, tired, neutral), each with a two-word description.
- **Runtime:** `LayaKit`, FluidUse's Laya CoreML runtime vendored under Apache-2.0 (`LunteApp/Sources/LayaKit`), running in the app's own process. No Python.
- **Model, the Heat Detector** (`HeatDetector`): `FluidInference/laya-coreml`, the 128-token int8 bucket plus `tokenizer.json`, in `~/Library/Application Support/Lunte/laya-coreml`.
  - It's 5 files and 482,843,099 bytes ("483 MB"), pinned to revision `7b8d7a2b…`.
  - Nothing downloads until you press Download. Each file arrives as `.part` and moves in only when its size and SHA-256 match; one that doesn't is deleted.
  - The request carries nothing of yours.
  - The first load compiles for the Neural Engine (about 20 s, once). After that it loads in under a second, answers in about 10 ms, and uses about 100 MB.
- **Fit:** the question takes 49 of the 128 tokens, leaving about 79 for your message; anything longer is cut on the right. Code blocks are removed first.
- **Socket:** only once the model is loaded does the app listen on `scorer.sock` (mode 0600). Until then, or if the download fails, the hook finds nobody listening, doesn't mark prompts `rated`, and the word list decides. Each rating is appended as a `heat` line and the watcher replays.

**Onboarding.** Until the log holds a `test` event, the popover is onboarding, in the panel's own style: the title row with "Lunte" and how many steps are done ("1 of 3"), the line "Keep it cool. Or go boom.", and under "Set up" three steps as rows, like networks in Wi-Fi, one at a time. The step you're on has its symbol in a blue circle, its button on the right and a line under it on what to do or how it's going; a done step has a check and goes grey; a step to come is just its grey title. Once the download has started you can move on, and the next step is the one you're on: the Heat Detector's circle goes grey and fills with one blue ring, the download to 80 % and the install the rest (about 20 s, creeping to 97 % until it's in). Tuning asks the model, so if you get there first, it simply starts once the model is in (the scorer tunes on load when the labels are newer); while it tunes, its circle fills a ring of its own, with no text. No spinners, and no progress in words. A step that finishes collapses as the next one opens, and the panel moves with them (`MenuPanel.expand`). There's no skipping a step.
1. **Heat Detector:** "Download a local model that measures the heat in your prompts, right on this Mac. 483 MB from Hugging Face.", with Hugging Face linking to the model's page (`HeatDetector.page`), and **Download**. Then the ring, and if it fails, the step is yours again with why and **Retry**.
2. **Connect to Claude Code:** "Adds Lunte's plugin, so it hears your prompts. Then start a new chat." and **Connect**. After it succeeds, the alert says to open a *new* chat, because Claude Code loads plugins when a session starts; an error shows in the row.
3. **Tune hot and cool:** "Paste the prompt into a new Claude Code chat. Your AI rates your recent prompts, and the model learns what hot and cool are for you." **Copy prompt** puts `Fuse.setupPrompt` on the clipboard (§8). Then its ring, or why it failed, with the button back; once tuned, "Tuned to you".

With all three done, the title row says "Ready" and one row takes their place: "Ready for your first Boom?" and "Open Claude Code and type “3 2 1 boom”.", with a copy button. Your AI's last line in the setup chat says the same.

Once onboarded, a Mac without the Heat Detector shows the download in the Club's row instead: a progress bar with a percentage, then "Setting up…", or **Retry download** if it failed, or **Get the Heat Detector**.

A new `test` event (less than 10 minutes old, not yet announced) lights a fuse with 2 s of silence and blows, with the whole show. The popover shows it like a real Boom: the title row says "Boom", then "Your first Boom. Everyone heard that." and "“3 2 1 boom”", and the Boom's line field, already filled in with "it was a test", sent with return. Sending shows the line and "Fresh fuse in 0:10"; ten seconds later you're onboarded. The test is never posted to the Club. Macs that were connected before this onboarding count as onboarded. While onboarding shows, Lunte Settings offers Skip onboarding; after it, Replay.

**The popover** opens from the fuse, which lives only in the menu bar. It reads like the system's own menu bar menus (Battery, Wi-Fi), with their margins: 308 points wide, 14 on the sides. It's a panel of our own, not an NSPopover, so it opens the way theirs do: no arrow, a material as bright as theirs (`.sheet`: the menu's own draws a darker grey) with rounded corners, its top 4 points under the item and its left edge on the item's, and the item lit while it's open. It grows and shrinks with its content with the top fixed, in step with it: opening Previously or a session expands over 0.25 s and the panel grows down with it, and closing collapses the same way, and closes on a click anywhere else, on the item again, or Escape. A block for you, then Today, Previously, the Club and Lunte Settings…, with dividers between; the rows you can click light up under the pointer. With a Boom showing, the whole sheet gets a red wash from the top, snapping on with no fade. `scripts/render-popover.sh` draws every state, light and dark, the same ones Xcode previews (`Previews.swift`, debug builds only), and `Lunte -PanelShot OUT.png` opens the real panel under the real item, draws it, and prints where it sat.
- **The title row:** "Lunte", and on the right what's left of the fuse, the way Battery shows its charge: "54 %". Once it's empty, the menu bar's word for what happened since (`FuseLook.word`): the tier's name, then Still burning or Calmed down. Both in plain grey, never coloured.
- **Two lines of text**, at a fixed height while a session is open: the fuse in a word ("Slow burn"), and in the last 10 minutes when the session ends if nothing else is sent ("Slow burn · session ends in 8 min"), never coloured, with the hottest prompt still burning under it. The word is built from what the fuse did, never a guess at your mood: `Game.word`, so Cool, Burning, Slow burn (burning for `slowBurn`), Cooling off (no new heat for 5 minutes) or Last third; or "Held it together" for 10 minutes after a close call climbs out, with no sound or notification. Hovering a dot shows that message instead: "6 min ago · hot", plus "cooled off" or "set it off", then its text on one line. Blown, the Boom stays picked while nothing is hovered: "12 min ago", and in the last 10 minutes "12 min ago · fresh fuse in 8:10", counting to `freshAt`, then your line about it, or the message that set it off until you've written one. Nothing in the popover is italic. With no session open: "Your next prompt starts a session".
- **The open session** as dots that wrap, oldest first: grey calm (heat under 0.35), orange heated, red boiling (0.85 and up), a soft green glow for cool, and the tier's emoji where it blew or escalated. Past eight rows they scroll, newest at the bottom, with no scroller. Like every list in the panel, their ends fade out softly where there's more to scroll (top, bottom or both), instead of cutting the rows off, and past 15 prompts a caption counts them: "30 prompts in the last 41 min". The caption's line is kept free from the first dot, and so is a row for the next dots under the last, at every length, so neither a new row nor the caption ever moves anything. A message Laya is still rating is a grey dot breathing, and the line says "rating…". The dots touch, so moving across them never drops the hover. **Easter egg, with no UI:** once you've written your line, each tap on the Boom's dot shaves 2 s off the wait, at most 60 s; when a hurried wait ends, the app appends a `rest` event. A new prompt resets the shave.
- **Your line about the Boom** (the Justify of GAME.md): right after the Boom's dot, the dots make room for a field with a faint "What happened?" in it, at most 40 characters, sent with return. It never says comment or roast, and there's no button. Then the Club's reactions take the same spot, and the dots carry on after it. Nothing invites staying quiet. It's saved on the Mac and, in a Club, sent as a `why` once the Boom has reached the relay: one typed while the fuse burns goes right after the Boom, never before it. If the Club misses it, an alert says so.
- **Your last session**, in place of the line and the dots, the first time the popover opens after a session closed: a fresh fuse's "100 %" in the title row (what was left, or the tier, where you point), "Last session · 1 h 5 min", `Game.sessionLine` one sentence a line, your line about its Boom, and its aura. Then the fuse across it (`Game.fuseLine`), in steps from its start to its close, at one hour to the full width so sessions compare at a glance, with clock times under it; a longer session scrolls, opening on the Boom or the fuse's lowest point, and a pinch zooms, out to the whole session: grey while full, orange while burning, red in the last third and from the Boom until the last burn cooled off, the tier's emoji at the Boom, and a dashed rise to the fresh fuse at the close. Pointing at it shows that moment in place of the facts: the time and what was left (the title row shows it too), or from the Boom on, the tier and the prompt that set it off. No other prompt shows in a past session. Shown once, counted when it's on screen, so another screen filling the popover, like the Heat Detector's, doesn't use it up.
- **The Club:** a row with a house (blue once you're in a Club, like the network you're on in Wi-Fi), the Club's name (or "Join a Club"), and a blue dot when something happened since you last opened the Club's window: someone else's Boom, line or join, or a reaction to yours. It opens the Club's own window, a place rather than a list: the Club's name and its people as faces (everyone seen joining; the relay keeps no list), then its last 100 events by day, read like a group chat, the newest at the bottom, where it opens. Each Boom says when it went off, in the middle, with no name ("💥 Boom · 14:12", or "Your Boom" on yours). Its owner's line, if they wrote one, is their chat bubble with their face and name, yours on the right in blue. The reactions sit under it as pills; on anyone else's Boom the 🧯 😂 🫂 pills throw one. Joins sit in between. At the bottom, the invite code with Copy, and Leave Club behind ⋯. Without a Club: what a Club is, Join a Club… and Create a Club…. While the Heat Detector isn't ready, its download sits in this row instead.
- **Today:** today's earlier sessions under the open one, newest first, three rows and then it scrolls, a row each like a network in Wi-Fi: the fuse at rest (`FuseIcon`, the menu bar's own drawing) at its menu bar size, in a pill, how many prompts, and how long ago it ended ("6 h ago"). How it went waits in its summary. Clicking one opens its summary under it. The summary showing as your last session isn't listed twice.
- **Previously:** the sessions before today, behind a row that opens like Other Networks in Wi-Fi, onto a list by day ("Yesterday") that scrolls past 240 points, each row with the time it started instead of how long ago. The section headers, Today and Previously, are grey and medium weight, lighter than the title. Local only, never a score.
- **Lunte Settings…**, the last row, like Battery Settings…, opens a window of its own: **Sound**, **Show model ratings** (debug: the line adds heat %, its source (Laya, or the word list when Laya isn't there or didn't answer in time), what it burns, the mood and the word list's signals; a spinner while Laya is rating), **Submit a prompt…** (a native dialog, "Something you want to see in Lunte?", with your name and a multi-line prompt; Submit sends it to the relay's prompt inbox (§5) and says "Thanks, it's in", or why it couldn't, prompt cut at 4,000 characters), Onboarding (Replay, or Skip while it shows), Check for updates and Quit.

**The Club.** The app polls every 30 s. Every notification is a silent banner: the bang is the only sound in the room.
- **Someone else's Boom:** a notification "💥 Boom in your Club" with 🧯 😂 🫂 actions, each of which posts a react.
- **A why on someone else's Boom, or a join:** a notification such as "Paal: …" or "Ola joined your Club".
- **Reacts never notify.** Those on your own Boom go on its card.
- **Catching up after being offline:** events older than 10 minutes go into the feed without a notification.
- **A Boom counts as yours** only once the relay has accepted it (201). Leaving a Club forgets your Booms and their secrets.
- **Run from Downloads:** if macOS runs the app from a temporary path (App Translocation), the app asks to be moved to Applications and doesn't link the hook.

**Sparkle.** `SUFeedURL` is `https://github.com/ProggePal/lunte-app/releases/latest/download/appcast.xml`. `SUPublicEDKey` gets set at release time, and the updater stays off while it's empty.

## 7. Build

`scripts/build-app.sh [--release]` builds both packages and assembles `dist/Lunte.app`:
- `Contents/MacOS/{Lunte,lunte-hook}`
- `Contents/Frameworks/Sparkle.framework`
- `Contents/Resources/{boom.wav,Lunte.icns,LayaKit-LICENSE.txt,plugin/}` (FluidUse's Apache-2.0 licence, which travels with the binary)
- `Contents/Info.plist`

A dev build is signed ad-hoc. `--release` signs with `Developer ID Application: Panter AS (BF4LY62Q92)` and the hardened runtime. Notarizing and the appcast are a separate release step.

**The fuse, while working on it.** A debug build started with `open dist/Lunte.app --args -FuseDemo YES` plays a whole session on the menu bar fuse in a loop, the screen's show included but without the sound, instead of the game's. `scripts/render-fuse.sh` draws it to `dist/fuse.png` (every state and move, frame by frame) and `dist/fuse.gif` (that session), with the same code as the menu bar, and the app's icon, `Resources/Lunte.icns`: the fuse the moment a prompt lights it, on a black squircle. In Xcode, open `LunteApp/Package.swift`, pick the `FuseKit` scheme and open `MenuFuse.swift` for the same previews, plus a live playground.

**The README's clips.** Both are a real Mac, recorded off the screen. `docs/clips/menubar.gif` is the menu bar alone, floating on a white backdrop (`menubar-dark.gif` on GitHub's dark card colour, for its dark theme): a fresh fuse lays itself out, burns, crawls through its last third and grows back green, made by `scripts/hero.sh bar`: the hook gets four prompts straight from a Terminal window, two mean and two kind. `docs/clips/fuse.gif` is the fuse over a small Terminal window with a real Claude Code in it, made by `scripts/hero.sh fuse`: `expect` types the same four prompts into Claude Code, with only Lunte's plugin, in a window the `LunteClip` profile titles only as Claude Code does, and Claude answers each in a line. The Boom isn't shown (`heat`, `cool`, `close`, `chain` and `boom` clips are there too). For both, a debug build started with `-HeroDemo <clip>` and a spare `$LUNTE_LOG` plays the clip's set script (`MenuBar.clips`) instead of the game, so your own log and Club never see the prompts, and ffmpeg records. macOS draws its recording badge over the item's left end, so the recordings start past it, and `render-fuse` paints out the dot it shows beside Control Center. The recordings are kept in `docs/clips/takes`, and `scripts/hero.sh gif fuse` (or `gif menubar`) frames them again without a new take; `gif menubar` also makes `docs/social-preview.png`, the picture a link to the repo shows, uploaded in its Settings. Terminal needs Screen Recording, once.

## 8. Your fuse

Your AI rates your past messages once, for heat and for cool, and Lunte learns how Laya's answers add up to each for you. Nobody labels anything by hand, and Lunte and your AI never talk directly: they share a folder, `~/Library/Application Support/Lunte/fuse`, and the `lunte-hook` commands.

- **The setup prompt** (`Fuse.setupPrompt`): `Let's set up Lunte. Look at my messages and tune the sensitivity and the vibes. Lunte's setup tool is at "$HOME/Library/Application Support/Lunte/lunte-hook": run it with setup for the steps. Let me know when you're done :)` It never contains the test phrase, so pasting it can't Boom, and it doesn't burn either.
- **`lunte-hook setup`** prints the steps for your AI (`Fuse.setupText`):
  1. List the messages (`lunte-hook messages`).
  2. Rate each for heat, 0–3 toward the assistant: 0 calm, 1 irritated, 2 angry, 3 furious. Heat means anger, not volume: capitals and swearing out of joy ("LETS GO") are 0, and sarcasm ("great, you broke it again") is heat.
  3. Rate each again for cool, 0–3: talking to the assistant like a best bud (slang, banter, hype, nicknames, casual thanks, happy swearing). 0 neutral, including a formal "please" or "thank you", 1 friendly, 2 buddy, 3 best bud. One message can be both hot and cool.
  4. Write `labels.json`.
  5. Write about 20 personal vibes to `vibes.json`, without showing them.
  6. Run `lunte-hook check-fuse`, which checks both files.
  7. Finish with one line in the chat telling you to type `3 2 1 boom`.
- **`vibes.json`**, written by your AI: `{"lunte": "fuse-vibes", "v": 1, "made", "vibes": [{"emoji", "label", "band", "topic", "when", "story"}]}`. `topic` is one of code, design, writing, business, voice, shipping, ideas, or "any" for vibes about mood, time or habits. A vibe without a topic gets one from Laya's topic question on its label and "when", kept only above 0.5; that fallback is rough, so the AI's own topic is preferred. About 20 personal vibes in Lunte's voice (dry, understated), spread over the bands, about the mood rather than the content: no quotes, no names, nothing private. `lunte-hook setup` tells the AI not to list them to you. `FuseVibes.problems` checks the shape, the lengths, and that every band has at least one vibe. The app reads the file at launch and whenever the folder changes.
- **`labels.json`**, written by your AI: `{"lunte": "fuse-labels", "v": 1, "rater", "made", "labels": [{"sid", "ts", "rating", "cool"}]}`, where `rating` is heat. Message references only, no text. `FuseLabels.problems` lists what stops tuning: the wrong `lunte` or `v`, heat or cool ratings outside 0–3, or fewer than 30 ratings. Files from before cool have no `cool`; they still decode and tune heat. `check-fuse` also reports every message without a `cool` (`FuseLabels.missingCool`), since setup rates both.
- **Candidates** (`Fuse.candidates`): every message the word list flags, up to a third of 300, plus an even spread of the rest, oldest first.
- **Tuning.** When `labels.json` is newer than `profile.json` (watched, 1 s debounce, and checked at launch once the model is loaded), the app:
  1. finds each rated message in the transcripts (same session, within 1 s), and needs at least 30
  2. asks Laya the 11 probes of `Scorer.probes` (~90 ms per message)
  3. turns every option's probability into a feature, `log(p + 0.0001)`
  4. trains `PersonalFuse`: a ridge regression on the 0–3 heat ratings over the standardised features, with the regularisation picked from 0.01–3 by 5-fold cross-validation
  5. trains a second `PersonalFuse` the same way on the cool ratings, from the same features, when at least 30 of the found messages have one
  6. saves `profile.json`, and `cool.json` for cool (or removes `cool.json` when there's no cool model)

  `fit` is the held-out AUC of irritated-or-worse against calm. Message text stays in memory only.
- **`profile.json`** and **`cool.json`**, written by the app: `{v, probes, mean, sd, weights, bias, lambda, trainedOn, fit, rater, made}`. A profile only applies if its `probes` match the app's; otherwise it counts as untuned.
- **Heat with a profile:** all probes are asked, and heat is the predicted rating divided by 3, clamped to 0…1. So furious is 1 (a Boom on a fresh stick), angry 0.67 and irritated 0.33. Without a profile, heat is P(frustrated) from the mood probe. The mood probe's top label always feeds the vibe line.
- **Cool with a cool model:** the same answers through `cool.json` give cool 0…1, logged in the heat line next to heat. Without a cool model, cool stays nil, and the game reads nil as 0.
