# Changelog

What changed for you in each version of Lunte.

## Unreleased

### Improvements
- **The fuse lives in your menu bar.** The 🧨 and its three little bars are now a real fuse. Heat lights its tip, and a burn eats it from the tip with sparks and ash. Cool feeds new fuse in from the other end, glowing green. When it blows, it says BOOM, then CHAIN REACTION and MELTDOWN if you keep at it, and calms down to a faint burst. A new session lays out a fresh fuse. The bar is gone from the popover; the menu bar says it all.
- **Keep it cool.** Lunte now reads a second thing in every message: cool, when you talk to your agent like a buddy. Heat burns the fuse and cool grows it back. To tune it to you, Replay onboarding and paste the new setup prompt: your AI now rates cool as well as heat.
- **Sessions.** A session lasts until you've been quiet for 30 minutes. You get one Boom per session; keep the heat coming and it turns into a Chain reaction, then a Meltdown. Funnier, never louder. Your fresh stick comes when the session ends.
- **Close calls.** The last third of the fuse is marked, and climbing back out of it gets you a quiet "Held it together".
- **Your last session.** The next time you open Lunte after a session, you see how it went: a heat line and one line on what happened. History keeps your past sessions by day; click one to see it again. It all stays on your Mac.
- **Aura.** Each session earns one award: 3 for a close call, 1 for your first cool session of the day. It shows on your sessions for now, and goes to your Club when Leagues arrive.
- **The whole session as dots.** Your dots now cover the session, not just the last 30 minutes, and the oldest fold into a line on long days. Cool messages glow green.
- **A quieter 💥.** Ten minutes after a Boom, the menu bar calms down to a faint 💥, so it doesn't shout for the rest of your session.
- **A softer Boom.** The fuse fizzes for a moment before it blows, which takes the jump out of the bang, and the bang itself is a notch quieter. With the sound off, you hear neither.
- **Fewer false alarms.** Tuned on 13 weeks of real use, the fuse lands around one or two Booms a week, and CAPS or "!!" on their own no longer burn it.

### Fixes
- The test Boom stays quiet when your sound is off.
- **Club notifications never give you away.** They used to ding on every Mac but yours, sometimes before the bang. Now your Club hears about a Boom only once it has gone off, in a silent banner you can still throw a 🧯, 😂 or 🫂 from.
- Reactions to your Boom show up on its card, without a notification.
- **Quitting doesn't lose your Boom.** Quitting or updating Lunte while the fuse burned used to lose the bang. Now the fuse lights again when Lunte opens, if the Boom is under 10 minutes old.
- **One bang per session.** A rating that came in late could move your Boom to an earlier message and set it off again, bang and all. Now a session bangs once, and your comment and your Club's reactions stay with it.
- **Shutting the lid doesn't give you away.** If your Mac went to sleep while the fuse burned, the bang used to go off the moment you opened it. Now that Boom stays quiet: it's on your card, with no sound or sparks, and your Club never hears of it.

## 0.2.2

### Fixes
- **Lunte opens on a new Mac.** Unzipping the download with a double-click left it looking tampered with, so macOS said it "could not verify Lunte is free of malware" and offered the Trash. It's signed and notarized by Apple, and now it stays that way when you unzip it.

## 0.2.1

### Improvements
- **Install the Heat Detector, on your terms.** A new Mac starts with one screen that explains it runs on your computer, so your messages stay there, and a Download button with its size. Nothing downloads until you press it, and you can watch the progress at the bottom of Lunte while you carry on.
- **Submit a prompt sends straight from Lunte.** No GitHub account or browser needed: write your idea and your name, press Submit, and it's with us.

### Fixes
- The Heat Detector download is checked file by file, so a broken or interrupted download is never used.

## 0.2.0

### Improvements
- **Lunte learns your temper.** During setup, one prompt lets your AI read your recent messages and tune Lunte to how you usually talk, so it blows when you lose it by your own standards.
- **Every message has a heat.** Hot messages burn the fuse, calm ones barely touch it, and heat cools off after half an hour, so a calm stretch gives you your fuse back without stepping away.
- **The Boom starts in your menu bar.** Sparks drip from the fuse, the screen dims for a second, and it blows. The bang comes a little after your message, so the room has to guess who it was.
- **Your last 30 minutes as dots.** Hover one to see what you wrote and how hot it was.
- **A better moment after a Boom:** the message that set it off, one timer to your fresh stick, and a Comment box ready to go.
- **Clearer setup:** one line explains Lunte, three steps get you going, and a test Boom you comment on shows it all works.
- **Quick and light:** heat is read on your Mac in a few milliseconds, with nothing extra to install. The first launch downloads Lunte's model once (about 470 MB).
- **Vibes, if you want them:** a dry one-liner about your session, some written just for you during setup. Off by default; turn them on in Settings.

### Fixes
- Messages from Claude's own helper agents no longer count as yours, so they can't set off a Boom.
- The menu bar says BOOM once it has blown, test Booms included.
- A message's heat shows up as soon as it's read, with a breathing dot while you wait.

### Misc
- Settings is simpler: Skip onboarding while it's showing, Replay onboarding after.
- Show model ratings lets you see the numbers behind each dot.
- **Submit a prompt:** suggest something for Lunte from Settings, written the way you'd ask an agent to build it. If we keep it, you're credited here.

## 0.1.0

### Improvements
- **First release.** A stick of dynamite in your menu bar that burns down when you lose your temper with Claude Code, and blows with a sound the whole room hears.
- **Own it or stay a mystery:** leave a short comment on your Boom, or don't.
- **Clubs:** make one or join a friend's, see when someone in it blows up, and throw them a 🧯, 😂 or 🫂.
- **Updates itself** from GitHub, signed and notarized.
