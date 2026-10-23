# Lunte

**When you lose it with your AI (more than you usually do), your laptop blows up. Everyone hears it. Own it, or stay a mystery.**

A Mac menu bar app for Claude Code. It's a prototype, with a handful of players so far.

## How it plays
- A stick of dynamite sits in your menu bar, and every message you send Claude has a heat.
- Calm messages barely touch the fuse. Hot ones burn it, and the heat cools off after half an hour.
- Too much heat at once and your laptop goes 💥: sparks from the menu bar, then a bang the whole room hears a few seconds later, so they have to guess who it was.
- Your Club gets the Boom on their Macs and throws you a 🧯, 😂 or 🫂. Comment on it, or stay a mystery.
- Step away for 10 minutes, or keep it calm for half an hour, and you get a fresh stick.

## Tuned to you
During setup, Lunte gives you one prompt for Claude Code. Your AI reads your recent messages and rates how heated they were, and Lunte tunes its heat detector to your normal. Nobody labels anything by hand.

## Privacy
Everything Lunte does runs on your Mac. Lunte never stores or sends your prompts. Only your Booms, reactions and comments go to your Club.
- Lunte reads heat with a small model on your Mac. It downloads once from Hugging Face on first launch (about 470 MB).
- The setup prompt asks your own AI to read your recent messages, so they go to your AI provider like any other chat. Lunte keeps only the ratings.

Read [the promise](docs/adr/0001-everything-runs-on-your-computer.md).

## Install
1. Download `Lunte-<version>.zip` from the [latest release](https://github.com/ProggePal/lunte-app/releases/latest), unzip it, and drag Lunte into Applications. It's signed and notarized, and it updates itself.
2. Open it, click the 🧨 in your menu bar, and follow the three steps: listen for new messages, activate the heat detector, and turn the heat up.
3. Join a Club with its six-letter code, or create one, from the house at the bottom of the popover.

You need a Mac with Apple Silicon, and Claude Code.

## Ideas
Something you want to see in Lunte? Choose Submit a prompt… in Lunte's settings, or open an issue here with the prompt you'd want an agent to run to build it. If it's good, we keep it, and you're credited in the [changelog](CHANGELOG.md).

## Credits
Heat is read by [Laya](https://huggingface.co/convaiinnovations/laya-multilingual) (Apache-2.0), running on your Mac through FluidInference's [CoreML build](https://huggingface.co/FluidInference/laya-coreml) and the [FluidUse](https://github.com/FluidInference/FluidUse) runtime (Apache-2.0).

Made in Oslo by Panter AS.
