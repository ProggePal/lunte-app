# Yell at your AI. Your Mac goes boom.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/clips/menubar-dark.gif">
  <img src="docs/clips/menubar.gif" alt="Lunte in a Mac menu bar: a fresh one lays itself out, burns, crawls through its last third, and grows back green">
</picture>

Lunte is a fuse in your menu bar. Angry prompts burn it, chill ones grow it back.

[![Download for Mac](https://img.shields.io/github/v/release/ProggePal/lunte-app?label=Download%20for%20Mac&logo=apple&style=for-the-badge&color=e8590c)](https://github.com/ProggePal/lunte-app/releases/latest)

**Your prompts are never stored or shared.**

However, if you start a Club with your friends, they'll get pinged every time someone blows up, but not who did it. Enjoy!

```
Hey Claude, install Lunte for me. It blows up my Mac if I get mad at you: https://github.com/ProggePal/lunte-app

Don't worry, it's only for show. The Mac is safe.
```

## How it works
![Lunte over Claude Code: two mean prompts burn it into its last third, two kind ones grow it back](docs/clips/fuse.gif)

- **Heat burns, cool grows.** Get mad at your AI and the fuse burns. Talk to it like your best bud and it grows back. Setup tunes both to how you talk.
- **Boom.** Burn through it, and a few seconds later your Mac blows up. Out loud. Keep the heat coming and it turns into a Chain reaction, then a Meltdown.
- **Sessions.** After 30 minutes without a prompt, you get a fresh stick and see how the session went.
- **Clubs.** Make a Club with your friends. Your explosions are shared anonymously. Write a line to take the heat, and they'll roast your agent.
- **Coming soon: Leagues.** Roasts, close calls and cool sessions earn your Club vibes, and Clubs race each other every day. Let the best vibes win.

## Install
1. Ask your agent to install it, with the line at the top. Or download `Lunte-<version>.zip` from the [latest release](https://github.com/ProggePal/lunte-app/releases/latest), unzip it, and drag Lunte into Applications. It's signed and notarized, and it updates itself.
2. Open it, click Lunte in your menu bar, and follow the three steps: download the Heat Detector (483 MB, once), connect to Claude Code, and tune hot and cool to you. Then type `3 2 1 boom` in Claude Code for your first Boom.
3. Join a Club with its six-letter code, or create one, from the Club row in the popover.

You need a Mac with Apple Silicon and Claude Code.

### For your agent
Installing Lunte for someone? Check it's an Apple Silicon Mac (`uname -m` says `arm64`), then run:

```bash
curl -fsSL "$(curl -fsSL https://api.github.com/repos/ProggePal/lunte-app/releases/latest | grep -o 'https://[^"]*/Lunte-[^"]*\.zip' | head -1)" -o /tmp/Lunte.zip
ditto -x -k /tmp/Lunte.zip /Applications
open /Applications/Lunte.app
```

If Lunte is in Applications already, just open it: it updates itself. Then tell them to click Lunte in the menu bar and follow the three steps.

## Questions
**Do you sell my prompts?**
No, we never even see them. Lunte scores each prompt on your Mac and keeps only the scores. The text is never saved, and it never goes anywhere it wasn't already going.

That includes setup: your own AI rates your recent prompts so Lunte learns how you talk, and that's just another chat with your AI. Read [the promise](docs/adr/0001-everything-runs-on-your-computer.md).

**So what does get shared?**
Nothing, unless you join a Club. Then your Club sees:
- your name
- your Booms: when they went off, never who
- the emoji you throw, with your name
- your line about a Boom, if you write one. It has your name on it, so that's your call.
- the vibes you add to the Club, never who earned what

Never your prompts, their scores, or how long you work. Later, a Club can go public and put its name and vibes on a public board.

Oh, and the whole room hears the boom.

**How does it work?**
Lunte plugs into Claude Code as a hook. Every prompt you send is scored by the Heat Detector, a small model running on your Mac (483 MB, downloaded once from Hugging Face during setup), and the scores move your fuse. Nothing ever shows up in your chat.

## Ideas
Something you want in Lunte? Choose Submit a prompt… in Lunte's settings and it comes straight to us. You can also open an issue here with the prompt you'd give an agent to build it. If we keep it, you're credited in the [changelog](CHANGELOG.md).

## Credits
Heat is read by [Laya](https://huggingface.co/convaiinnovations/laya-multilingual) (Apache-2.0), running on your Mac through FluidInference's [CoreML build](https://huggingface.co/FluidInference/laya-coreml) and the [FluidUse](https://github.com/FluidInference/FluidUse) runtime (Apache-2.0).

Made in Oslo by Pål Sørvik.
