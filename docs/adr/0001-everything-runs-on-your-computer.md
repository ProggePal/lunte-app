---
status: accepted
---
# Everything runs on your computer; only what you choose to share leaves it

The product reads every prompt a person sends to their AI, which is the most sensitive text on their machine.

We decided that all analysis runs locally with no network call: the Classifier, the Lunte, Booms, the Card, your reading, temper types, your patterns and `lunte why`. Lunte never copies prompt text. Its log holds a timestamp, a mood label and counts. For `lunte why` it keeps only a pointer into the transcript Claude Code already stores.

Only these leave the computer:
- **The Boom sound**, which the room hears. The install says so.
- **Booms, Claims and Reactions** sent to the person's Club through the Relay, once they've joined a Club. That covers the Club, the time, what lit it (kinds, never words), their comment and emoji.
- **Weekly counts** (Burns, Booms, Meltdowns) for You vs Norway, anonymously, and only if the person opts in.
- **Cards** and anything else the person pastes themselves.

This is a public promise made in LinkedIn posts, so walking it back costs trust, not just code.

Updated 22 Oct 2026 for the game redesign.

## Considered options

- **Hosted classifier (TypeSafe Jev).** Better mood scoring, cheap, but hosted only, so every prompt would go to a US server. Rejected because it makes the promise false.
- **Friday opt-in LLM call over the week's prompts.** Tempting for richer Cards. Rejected for v1. It sends prompt text off the machine, and Anthropic's usage policy restricts using Claude to infer a person's emotions. A local model (Laya) is the allowed upgrade path.
- **Copying the prompt that lit a Boom into Lunte's log.** Rejected. Claude Code already stores it, and a pointer gives `lunte why` without a second copy.
- **A forced Friday reveal of unclaimed Booms.** Rejected. Outing people breaks "own it, or stay a mystery", and the Club's owning-up score is pressure enough.
- **Free-text replies between Club members.** Rejected. The Relay would carry, and need to moderate, text people write about each other. Reactions are emoji only.
- **No sharing at all.** Rejected. The Club is the game, and what goes to it is the person's choice.

## Consequences

- **The Classifier** is word lists and heuristics in a dependency-free script. Mood is coarse; accept it. Per-person calibration absorbs a consistent misread, and Laya stays opt-in flavour.
- **The hook prints nothing.** People see Lunte in the menu bar and the app, never in the chat.
- **What the Relay stores:** Club, time, the kinds of Burn, comments, emoji, and anonymous weekly counts for You vs Norway. Never prompt text, never per-prompt rows.
- **Who the Relay can identify:** each Boom gets a random id on the person's machine, so the Relay learns who a Boom belongs to only from a Claim.
- **Terminal commands, not slash commands.** `lunte why`, `lunte claim` and the Card are terminal commands or app actions, because slash command output goes into the model context and so to Anthropic.
- **`lunte why` can come up empty.** Claude Code deletes old transcripts (30 days by default), so the pointer goes stale; accept it.

## Amended 23 Oct 2026 (Lunte 0.2.0)

- **Heat is read by Laya on the Mac.** It's no longer opt-in flavour. The model (`FluidInference/laya-coreml`) downloads once from Hugging Face on first launch; that request carries nothing of the person's. The word list is the fallback until the model loads.
- **The fuse setup prompt is the one exception to "no network call", and the person runs it.** It asks their own AI (Claude Code) to read their recent messages and rate how heated they were. Those messages go to their AI provider, in their own chat, like any other request, and only because they pasted the prompt. Lunte itself still sends nothing; it keeps only message references and 0–3 ratings, never text. Skipping it leaves the fuse untuned.
- **Open question:** Anthropic's usage policy restricts using Claude to infer a person's emotions. Here it's a person rating their own messages, by choice, but check the policy wording before a public launch, and drop or replace the setup prompt if it doesn't hold.
