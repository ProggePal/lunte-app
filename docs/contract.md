# Prototype 1 contract

The shared contract between the pieces. Builders code against this; change it here first.

## Layout

```
app/
  LunteCore/    Swift package: LunteCore (logic), lunte-hook (the Claude Code hook), tests
  LunteApp/     Swift package: Lunte (the menu bar app), depends on ../LunteCore, Sparkle, LayaKit (vendored) and FuseKit (the menu bar fuse)
  relay/        Cloudflare Worker + one Durable Object per Club
  plugin/       Claude Code plugin + marketplace, bundled into the app
  Resources/    boom.wav, Info.plist
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

- **test** beats everything: `3 2 1 pow`, with any spaces or punctuation between (`3, 2, 1… POW!`, `321 pow`). It's the onboarding phrase.

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
- **The vibe** (`Vibe`): one dry line about the last 30 minutes, shown in the popover only, never sent.
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
- **A prompt:** while the model rates it (`Event.awaitingRating`), a faint breeze ripples through the coils. Then one of four things happens. Nothing: the breeze dies down. Heat: the tip catches and burns its bite away, right to left (heat² over the stick): the flame flares and runs back, sparks fly, the burnt bit glows and falls as ash, and what's left springs apart. In the last third it crawls instead: it creeps, nearly stops, gutters and creeps on (`Ease.hesitate`), so you can't tell if it'll stop in time. The flame burns on for 2.5 s, 3.5 s past half, or 5 s in the last third (`FuseScene.flameFor`), amber, orange or red and trembling, then goes out in a puff. Cool: new fuse feeds in at the start, left to right, green with twinkles, squeezing the coils together. Both: the two at once, the start growing by the rest of the change. Climbing out of the last third flashes green.
- **Burnt through**, the Boom's own burn crawls the same way all the way down, the flame dies at the start in a puff, and then there's nothing, as if it went out. In the last 3 s before the bang (`FuseScene.takeover`) it glows there again and sparks shoot out, brighter and faster, and its last 1.4 s (`FuseScene.slowMo`) slow to a twelfth of normal speed (hitstop, from hq's game-feel research).
- **The bang:** a flash, a shockwave, a spray of sparks and a jolt where the fuse began; 0.35 s later the word lands with a bounce.
- **Blown and calm**, there's no fire: an SF Symbol and a word in the menu bar's own colour and font, still unless they change. First `burst.fill` and the tier's name (Boom, Chain reaction, Meltdown), for at least 5 s (`FuseScene.nameFor`). Then `flame.fill` "Still burning" while the heat toward the next tier is a quarter of the way or more, and `wind` "Cooled off" once it's quiet (10 minutes after the Boom or its last escalation), dimmed a little. Otherwise the tier's name. A change swaps them quietly: the old one rises away, the new one springs up from below, and a new tier gives the symbol a small pop. The item widens for the longest of them and stays that wide until the session ends, so the menu bar doesn't jitter.
- **A new session** feeds in a fresh fuse from the left.
- **Before it's connected** the coil is faint. With Reduce Motion every change snaps. Its tooltip and VoiceOver label say how much fuse is left, or the tier.

**Watching the log.** It watches `events.jsonl` with a file-system source and a 1 s debounce, reopening the file if it's created or replaced. On every change it replays the log. For a new Boom:
- **Not yet announced and less than 10 minutes old:** light the fuse: a random 5–60 s wait, so the room has to guess who it was. The wait is silent, as if the fuse went out. In its last 3 s the screen darkens around a warm glow at the fuse and sparks shoot out of it; in the last 1.4 s they slow until they nearly hang, and unless the sound is off, a soft fizz (0.4 s of synthesised noise) starts. Then it blows from the icon (a flash of the whole screen, two shockwaves, and a burst of sparks and embers falling down the screen as the dark drains away, native Core Animation in a click-through overlay) and plays `boom.wav` right after the fizz, both capped at 0.6 of the Mac's volume. At that moment, sound or not, it posts the Boom to the relay if you're in a Club, so no Club Mac hears of it before the bang. If the Mac slept through the wait (more than 2 s late by the wall clock, `Blast.lateBy`), there's no dim, sound, burst or post; the Boom stays in the log and on its card. With Reduce Motion there's only the wait and the sound. The onboarding test burns for 3 s.
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

**The first screen** on a Mac without the Heat Detector fills the popover:
- 🧨, "Install the Heat Detector", and "Lunte reads the heat in your messages with a small model that runs on this Mac, so your messages stay on this computer."
- **Download · 483 MB**, and a small **Not now**.

Pressing Download moves on to onboarding. Until the detector is ready, the Club's place in the footer shows the download: a progress bar with a percentage, then "Setting up…" during the first compile, or **Retry download** if it failed. After Not now, that place offers **Get the Heat Detector**. Without the detector, the word list rates your messages.

**Onboarding.** Until the log holds a `test` event, the popover shows "Light your first fuse", the line "Lunte hears how you talk to your AI. Lose your temper, and it blows.", and a checklist:
1. Connect to Claude Code. After it succeeds, the alert says to open a *new* chat, because Claude Code loads plugins when a session starts.
2. Make Lunte measure the heat in your messages: "Copy prompt" puts `Fuse.setupPrompt` on the clipboard, to paste into a new Claude Code chat (§8). The step shows the tuning progress, or why it failed, and is ticked once tuned.
3. Light up Lunte. Your AI's last line in the chat tells you to type `3 2 1 pow`. Once you're tuned, the phrase also shows here as a backup, with a copy button.

A new `test` event (less than 10 minutes old, not yet announced) lights a 3-second fuse and blows. The popover shows "Your first Boom" and "Everyone heard that. Comment:", with the field already filled in with "it was a test". Commenting shows the comment and "Fresh stick in 0:10"; ten seconds later you're onboarded. The test is never posted to the Club. Macs that were connected before this onboarding count as onboarded. While onboarding shows, the gear offers "Skip onboarding"; after it, "Replay onboarding".

**The popover** opens from the fuse. The fuse itself lives only in the menu bar. Top to bottom, and with a Boom showing, the whole sheet gets a red wash from the top, snapping on with no fade.
- **Held it together:** for 10 minutes after a close call climbs out, a green line says so. No sound, no notification.
- **Or the Boom:** the tier's emoji and name (Boom, Chain reaction, Meltdown), when it last went off, and one timer, "Fresh stick after 30 quiet minutes · 24:10", counting to `freshAt`. **Easter egg, with no UI:** once you've justified, each tap on the 💥 shaves 2 s off the wait, at most 60 s; when a hurried wait ends, the app appends a `rest` event. A new prompt resets the shave.
- **One text slot**, two lines and a fixed height: the hovered message, or with nothing hovered, the message that set off the Boom (serif italic, centred), else the hottest one still burning, else your latest. Above it, "19:34 · hot", plus "cooled off" or "set it off". Hovering the vibe line shows its story here instead.
- **Comment** (the Justify of GAME.md), under a Boom: the field is open from the start, at most 40 characters, with a Comment button and your Club's reactions beside it. Nothing invites staying quiet. It's saved on the Mac and, in a Club, sent as a `why` once the Boom has reached the relay: one typed while the fuse burns goes right after the Boom, never before it.
- **The vibe line:** the session's vibe (§4), emoji and label, "✨ new" the first time it ever shows, or "Reading the room…".
- **The open session** as dots that wrap, oldest first: grey calm (heat under 0.35), orange heated, red boiling (0.85 and up), a soft green glow for cool, and the tier's emoji where it blew or escalated. Past 56 dots the older ones fold into "N earlier" and a thin heat line. A message Laya is still rating is a grey dot breathing, and the slot says "rating…". The dots touch, so moving across them never drops the hover.
- "12 messages from Claude Code", then the Club's latest two events.
- **Your last session:** the first time the popover opens after a session closed, a card with its length, a small heat line, `Game.sessionLine` and its aura. Shown once, counted when the card is on screen, so another screen filling the popover, like the Heat Detector's, doesn't use it up.
- **History:** past sessions, newest first, grouped by day, each opening its card. Local only, never a score.
- **The footer:** sound; the Club (a house and its name, or "No Club") with its actions; a gear with Skip onboarding (while it shows) or Replay onboarding, **Vibes** (off by default; off means no vibe line, no vibe picking and no topic question), **Show model ratings** (debug: the slot adds heat %, its source (Laya, or the word list when Laya isn't there or didn't answer in time), what it burns, the mood and the word list's signals; a spinner while Laya is rating), **Submit a prompt…** (a native dialog, "Something you want to see in Lunte?", with your name and a multi-line prompt; Submit sends it to the relay's prompt inbox (§5) and says "Thanks, it's in", or why it couldn't, prompt cut at 4,000 characters), Check for updates and Quit.

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
- `Contents/Resources/{boom.wav,LayaKit-LICENSE.txt,plugin/}` (FluidUse's Apache-2.0 licence, which travels with the binary)
- `Contents/Info.plist`

A dev build is signed ad-hoc. `--release` signs with `Developer ID Application: Panter AS (BF4LY62Q92)` and the hardened runtime. Notarizing and the appcast are a separate release step.

**The fuse, while working on it.** A debug build started with `open dist/Lunte.app --args -FuseDemo YES` plays a whole session on the menu bar fuse in a loop, the screen's show included but without the sound, instead of the game's. `scripts/render-fuse.sh` draws it to `dist/fuse.png` (every state and move, frame by frame) and `dist/fuse.gif` (that session), with the same code as the menu bar. In Xcode, open `LunteApp/Package.swift`, pick the `FuseKit` scheme and open `MenuFuse.swift` for the same previews, plus a live playground.

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
  7. Finish with one line in the chat telling you to type `3 2 1 pow`.
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
