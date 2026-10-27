# Changelog

What changed for you in each version of Lunte.

## Unreleased

### Improvements
- **Cool means cool.** A prompt turns green when you talk to your agent like a buddy, not just politely, and only green prompts grow your fuse back. Friendly stays neutral, so a green dot is worth something.
- **Aura is now vibes.** What a session earns says so: "+3 vibes".
- **A session worth posting.** Dive into one and it tells the turn and the comeback: the prompt that burnt it, and under it the one that brought it back. Swears show starred, so it's safe to screenshot, and its foot says your Club and Lunte.
- **Hear it again.** Diving into a session plays its fuse and its Boom out loud as it runs back, quieter than the real thing and as your sound effects say. Point along the line and it goes quiet.

## 0.4.1

### Improvements
- **Dive into a session.** Click one and it opens like a Control Center module: its fuse grows big and plays the session back, its heat runs along a small line over the clock, and the prompt it turned on shows in your own words. Point along the line to find any prompt, click for the next one, or drag across a stretch to see when it ran and how many prompts it had.

  ![Diving into a session](https://raw.githubusercontent.com/ProggePal/lunte-app/main/docs/clips/session.gif)
- **Every session is its own fuse.** Each one in your list is a little copy of your fuse as it ended: its burns left as ash, a Boom left as a scorch.
- **A smaller popover.** Your sessions show today's, or this week's, this month's or all of them, five at a time. The Club and Settings sit in one quiet footer, with how many prompts you've sent today.
- **Your fuse, prompt by prompt.** Point at your dots and the percentage shows what each prompt left of your fuse. Cool dots are a clearer green, and the ones that were hot and cool at once show both.
- **Missing cool?** If you set Lunte up before it learned cool, it now says so, and Redo setup tunes it.

### Fixes
- No more "Setting up…" flash when Lunte starts.
- A prompt's text no longer shows Claude Code's own notes.
- Lunte rests completely while the popover's closed, and long sessions draw faster.

## 0.4.0

### Improvements
- **A whole new Boom.** A real fireball, sparks and smoke, and a new bang. Every Boom is a little different.
- **Suspense, then silence.** Near the end your fuse crawls, stalls and drips, so you never know if it'll make it. A Boom does the same, races out, goes quiet… then blows. No more dark screen.
- **Hear your fuse.** Pick your sound effects in Settings: Boom is just the Boom, as before. Sizzle adds your fuse burning, hotter and higher near the end. Fireworks adds the rest.
- **Instant.** Your fuse reacts the moment you hit Enter.

## 0.3.0

### Improvements
- **A simpler popover.** It reads like your Mac's own menus now, Battery and Wi-Fi's margins and all. At the top, Lunte and how much fuse is left, like your battery's charge; once it's empty, what happened since, like Still burning or Calmed down. Under it, the fuse in a word, like Slow burn or Last third, and in its last 10 minutes, when your session ends. Under it, your session as dots: point at one to see that message. After a Boom, the dots make room right after it for one line about it, if you want; press return to send it, and it stays there as your bubble, with your Club's reactions popping in under it; point at one to see who. Today's earlier sessions sit right under yours, and the ones before open from Previously, like Other Networks in Wi-Fi. It opens like Battery's too, with no arrow and your fuse lit while it's open. Lunte Settings… is the last row, and opens a window with the sound and the rest.
- **Clearer setup.** Three steps, one at a time: download the Heat Detector, connect to Claude Code, and tune hot and cool to you. Each says what to do while it's the one you're on, and you don't wait for the download: it fills a ring while you go on. Then: ready for your first Boom? Open Claude Code and type “3 2 1 boom”. Your first Boom looks like every Boom after it.
- **Your Club gets its own window.** One row in the popover, with a dot when something's new, opens it: your Club's people, then every Boom like a group chat, with the line its owner wrote as their bubble, if they did, and reactions you can throw with a click.
- **The fuse lives in your menu bar.** The 🧨 and its three little bars are now a real fuse, and it reacts to each prompt you send. While Lunte reads it, a breeze runs through it. Heat lights it and burns a bit away with sparks and ash, then the flame goes out. Cool feeds new fuse in from the other end, glowing green. In the last third the flame crawls and stutters and your screen dims a little, so you never know if it'll stop in time. If it burns right through, it races to the end, the flame dies, the screen goes dark, and nothing happens… for a second or a few. Then it blows, starting in slow motion: a flash, sparks and smoke down your screen. Then your menu bar just says Boom, then Chain reaction and Meltdown if you keep at it, Still burning while the heat keeps coming, and Calmed down once it's quiet. A new session lays out a fresh fuse. The bar is gone from the popover; the menu bar says it all.

  ![The fuse in the menu bar](https://raw.githubusercontent.com/ProggePal/lunte-app/main/docs/clips/menubar.gif)
- **Keep it cool.** Lunte now reads a second thing in every message: cool, when you talk to your agent like a buddy. Heat burns the fuse and cool grows it back. To tune it to you, Replay onboarding and paste the new setup prompt: your AI now rates cool as well as heat.
- **Only what you typed counts.** Text you paste, images, and the notes your app adds ("Please continue from where you left off") no longer burn your fuse or grow it. And setup now asks your AI to rate some of your friendliest messages too, so Lunte learns your cool from real banter. Replay onboarding to retune.
- **Grow your fuse.** Every session starts at 100 %, with room to grow. Cool with nothing left to mend makes your fuse longer, up to 125 %, its full three coils, and it stays that long until the session ends. Burns still heal after 30 minutes.
- **Sessions.** A session lasts until you've been quiet for 30 minutes. You get one Boom per session; keep the heat coming and it turns into a Chain reaction, then a Meltdown. Funnier, never louder. Your fresh stick comes when the session ends.
- **Close calls.** The last third of the fuse is marked, and climbing back out of it gets you a quiet "Held it together".
- **Every session gets a name.** When a session ends, Lunte names it for what you did and how it went: "Mad push to prod", "Business plan hours", "Brainstorm firestorm", "Kaboom". Never a telling-off. Your AI writes names just for you when you tune Lunte, and they come first.
- **Your sessions, at a glance.** Today lists your sessions, each with its own fuse, its name and the aura it earned, and a dot on the newest until you open it. Open one for its story ("Up, down, and up again."), what its aura was for, and its fuse in bars like Battery's chart, with the stretches where you were cool marked like charging. It all stays on your Mac.
- **Aura.** Each session earns one award: 3 for a close call, 1 for your first cool session of the day. It shows on your sessions for now, and goes to your Club when Leagues arrive.
- **The whole session as dots.** Your dots now cover the session, not just the last 30 minutes, and on long days they scroll. Cool messages glow green.
- **A quieter 💥.** Ten minutes after a Boom, the menu bar calms down to a faint 💥, so it doesn't shout for the rest of your session.
- **A softer Boom.** The fuse fizzes for a moment before it blows, which takes the jump out of the bang, and the bang itself is a notch quieter. With the sound off, you hear neither.
- **Fewer false alarms.** Tuned on 13 weeks of real use, the fuse lands around one or two Booms a week, and CAPS or "!!" on their own no longer burn it.
- **Lunte has an icon.** The menu bar's fuse, lit, on black. You'll see it in Finder, in notifications and when Lunte updates.

### Fixes
- The test Boom stays quiet when your sound is off.
- **Club notifications never give you away.** They used to ding on every Mac but yours, sometimes before the bang. Now your Club hears about a Boom only once it has gone off, in a silent banner you can still throw a 🧯, 😂 or 🫂 from.
- Reactions to your Boom show up on its card, without a notification.
- **Quitting doesn't lose your Boom.** Quitting or updating Lunte while the fuse burned used to lose the bang. Now the fuse lights again when Lunte opens, if the Boom is under 10 minutes old.
- **One bang per session.** A rating that came in late could move your Boom to an earlier message and set it off again, bang and all. Now a session bangs once, and your comment and your Club's reactions stay with it.
- **Shutting the lid doesn't give you away.** If your Mac went to sleep while the fuse burned, the bang used to go off the moment you opened it. Now that Boom stays quiet: it's on your card, with no sound or sparks, and your Club never hears of it.
- **A resumed chat counts once.** Claude Code copies a chat's messages when you resume or fork it, and Lunte used to read those copies as new messages when it tuned your fuse. Now each message counts once.

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
