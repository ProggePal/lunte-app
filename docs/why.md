# Why the rules are what they are

One entry per game rule: the rule, the principle behind it, how strong the evidence is, and one public source. The code points here with `// Why:` comments, and the tests that guard a rule are named after it, so a change that drifts from the reason trips one. Change a rule's entry here before you change the rule.

The menu bar fuse's feel has entries too, from `just-the-fuse` on. Most of those are craft, tuned by eye frame by frame, so they also say what was **tried** and dropped. Don't bring one of those back without saying why it would land differently now, and render the fuse before and after any change (`scripts/render-fuse.sh`).

**Evidence:**
- **Strong:** many studies, or a meta-analysis, agree.
- **Mixed:** the findings are real, but samples are small, replications failed, or big conditions apply.
- **Weak:** a framework, an anecdote, or untested craft.

## feedback-not-reward
- **Rule:** The fuse moving is feedback, not a reward. The rewards come from people: the laugh, the roast and the race. A roast's worth is decided by the Club's reactions, never by Lunte.
- **Principle:** Relatedness. Motivation lasts when an activity feeds autonomy, competence and relatedness, and among online multiplayer players each one predicted enjoyment and future play.
- **Evidence:** strong, mostly correlational.
- **Source:** [Ryan, Rigby & Przybylski 2006](https://doi.org/10.1007/s11031-006-9051-8)

## two-clocks
- **Rule:** The player's own feedback is instant: within 0.1 s, 1 s at worst. The breeze starts as the hook hands your prompt over, about 15 ms after Enter. The room's Boom comes after the fuse's 2.8 s race and a random 1–3 s of silence: enough to blur who it was, and short enough that the silence stays suspense rather than a wait.
- **Principle:** Perceived causality. People see "that made that happen" only when the effect follows at once, and even a 160 ms stagger cut causal ratings by about a third. Instant keeps the player's sense of agency; the delay breaks the room's link to the culprit.
- **Evidence:** strong for the effect, mixed on the exact window.
- **Source:** [White 2017](https://doi.org/10.1007/s00426-017-0853-y)

## juice-inverted-u
- **Rule:** Most prompts stay silent. The menu bar's small juice budget goes on a few moments: the Boom, the roast and the close call. The fuse's own sounds are yours to turn on ([fuse-sounds-opt-in](#fuse-sounds-opt-in)).
- **Principle:** Juice follows an inverted U. Medium and high juice beat both none and extreme on experience, motivation and play time (Kao 2020), and in a pre-registered study of 1,699 players, amplification that blurred the link from action to outcome lowered motivation (Kao et al. 2024).
- **Evidence:** mixed.
- **Source:** [Kao 2020](https://doi.org/10.1016/j.entcom.2020.100359)

## silence-then-boom
- **Rule:** The bang comes straight out of the silence after the build-up, with nothing before it. A close call ends instead the way cool ends anything: it grows back.
- **Principle:** Suspense lives in the gap, and a sound in it gives the answer away. A faint sound 30–500 ms before a loud one does dampen the startle reflex (prepulse inhibition), but the crawl and the run-out already say it's coming, and the volume cap keeps the bang a cartoon ([juice-inverted-u](#juice-inverted-u)).
- **Evidence:** strong in the lab for prepulse inhibition; giving it up here is craft, by ear.
- **Tried:** a 0.4 s fizz just before the bang, for prepulse inhibition: it broke the silence the build-up had earned. If the bang ever startles, soften its attack rather than bring the fizz back.
- **Source:** [Graham 1975](https://doi.org/10.1111/j.1469-8986.1975.tb01284.x)

## one-boom-per-session
- **Rule:** A session Booms once. More heat escalates that Boom instead of setting off another, and it still counts as one Boom.
- **Principle:** Venting feeds anger. Across 154 studies, arousing activities didn't reduce anger and calming ones did, so the game must never pay out more for more rage.
- **Evidence:** strong.
- **Source:** [Kjærvik & Bushman 2024](https://doi.org/10.1016/j.cpr.2024.102414)

## tiers-flavour-not-volume
- **Rule:** The tiers (💥 Boom, 💥💥 Chain reaction, ☢️ Meltdown) escalate in flavour, a name and an emoji, not in loudness or juice. After a Boom, each further half a stick of heat within 30 minutes steps it up one tier, so most Booms stay plain and a Meltdown is rare.
- **Principle:** Venting feeds anger. Louder tiers would put the most juice on continued rage, and they'd point at whoever is still raging.
- **Evidence:** strong that venting fails; how a tier should sound is craft. Tuned on a replay of 13 weeks of one player's real prompts: this gives 62–79% Booms, 14–38% Chain reactions and 0–7% Meltdowns. A whole stick per tier left 93–100% of Booms plain. Counting the whole session made up to 31% Meltdowns, because half the heat after a Boom lands more than 30 minutes later, and stepping up on every further hot prompt made 87% of them Meltdowns.
- **Source:** [Kjærvik & Bushman 2024](https://doi.org/10.1016/j.cpr.2024.102414)

## heat-not-volume
- **Rule:** Heat is anger, not volume. When the word list decides, `!!` and CAPS on their own don't burn: they only turn a telling-off into losing it. Swearing and telling off still count.
- **Principle:** Volume amplifies a feeling; it doesn't carry one. In a rule-based sentiment model that matched human raters, exclamation marks and capitals raise the intensity of the sentiment already in a text without changing its direction, so on their own they say nothing about anger.
- **Evidence:** mixed: one well-validated model. Tuned on a replay of 13 weeks of one player's real prompts: a tuned model rated the prompts flagged only by `!!` at a median heat of 0.15 and those flagged only by CAPS at 0.00, yet 8 of the 14 word-list Booms came from a single prompt, 5 of them flagged only by `!!` or CAPS.
- **Source:** [Hutto & Gilbert 2014](https://doi.org/10.1609/icwsm.v8i1.14550)

## cool-mends
- **Rule:** Cool grows the fuse back. A cool prompt mends some of what's burning, never below zero, and a prompt that's hot and cool at once, roasting your agent live, burns less than the heat alone. What it has spare grows the stick ([cool-grows](#cool-grows)).
- **Principle:** Humour as reappraisal. Good-natured humour lowered negative feeling more than mean humour did. Lunte rewards what you do with the anger, not the anger.
- **Evidence:** mixed: small samples.
- **Source:** [Samson & Gross 2012](https://doi.org/10.1080/02699931.2011.585069)

## close-call
- **Rule:** When the fuse gets into its last third and climbs back out without a Boom, that's a close call: one per dip, credited the moment it climbs out, and worth aura. Exactly a third left counts, whatever the floating point says. It's never faked, and the fuse is never shown closer than it was.
- **Principle:** Competence and relief. "I held it together" feeds competence, one of the needs that predicts enjoyment, and a reward works best right after the act.
- **Evidence:** strong for competence, mostly correlational. Tuned on a replay of 13 weeks of one player's real prompts: the last third gives 1.3 close calls a week (2 in the hot last month), about 1.3 per Boom, rare enough to mean something and common enough to happen. The last quarter gave 0.9 a week, and the last half 3.2, which is too cheap.
- **Source:** [Ryan, Rigby & Przybylski 2006](https://doi.org/10.1007/s11031-006-9051-8)

## cool-grows
- **Rule:** Every session starts at 100 %, with room to grow. Cool with nothing left to mend grows the session's fuse by half its spare mend, up to 125 %, which is drawn as the whole fuse: three tight coils. Burns heal after 30 minutes as before; growth stays until the session closes or Booms. The fuse moves by exactly what each prompt did, and the only marks are where a rule changes: the last third, 100 % and full.
- **Principle:** Endowed progress and the goal gradient. A head start toward a visible goal raises completion, and effort speeds up near it. A session that could only lose fuse had nothing to be proud of; growth gives it a gain. Growth stays, so there's nothing to keep alive ([no-streaks](#no-streaks)), and it's capped feedback, never points ([aura-not-work](#aura-not-work)).
- **Evidence:** mixed for endowed progress, strong for the goal gradient. Replayed on one player's real sessions (25 Aug–25 Oct, 223 sessions, model heat, a cool model trained on 300 setup ratings with a fit of 0.82): 129 sessions end above 100 % and 5 reach full. Booms stay at 1.1 a week with growth or without, since cool's mend already takes them from 1.4 and the thermostat holds the rate; sessions with a close call go from 13 to 12. So growth changes how a session ends, not how often you blow. On setup's old pick, an even spread with only 29 cool messages in 300, the cool model was too weak to say (0.63): it called "make no mistakes, idiot" cool.
- **Tried:** two coils at 100 % and three at 150 % (today's look, the one people know, is better as full); full at 115 % (you can't see it grew); growth at the full mend (two banter prompts fill it, so there's no climb).
- **Source:** [Nunes & Drèze 2006](https://doi.org/10.1086/500480)

## session-names
- **Rule:** A finished session gets a name for what you did and how it went ("Mad push to prod", "Business plan hours", "Kaboom"), never for what you did wrong or how the assistant took it: no blame and no anger words, because the aura already does the scoring. Facts pick the names that fit: the energy from what the fuse did, and the activity from the session's topic, or else the time of day. Then taste picks among them: the names your AI wrote at setup come first, a name never repeats in a day, and the one used longest ago comes round next. Without the Heat Detector there are no topics, so the time-of-day names stand in. Under three prompts gets a short name.
- **Principle:** Identity and a laugh. "This is me" keeps a history worth opening, a benign joke turns a bad hour into a story, and variety in flavour keeps it fresh without putting chance in what you earn. Names are true or they aren't shown: a wrong name breaks trust the way a faked near-miss does.
- **Evidence:** weak for names as such (craft), strong for the parts: peak-end, and good-natured humour as reappraisal. Replayed on one player's week: names from facts were all true; a model's or a rotation's were often false.
- **Tried:** Laya picking a name from a text-free summary (it called 09:05 "Late-night grind" and a voice session "Pixel fussing", at 30–60 % sure); rotating names within a band (true only by luck); names that report behaviour ("A little prickly", "Mildly offended": they scold); clock times in the story ("held it together at 17:13": nobody remembers a time); prizes for prompts, best bud and hottest take (they didn't tell the line's story and put the model's misreads on show; parked for achievements); a last-session card pinned at the top (awkward; Today holds sessions now).
- **Source:** [Kahneman et al. 1993](https://doi.org/10.1111/j.1467-9280.1993.tb00589.x) · [Samson & Gross 2012](https://doi.org/10.1080/02699931.2011.585069)

## session-story
- **Rule:** Opened, a session tells its shape in one kind line from the facts ("Up, down, and up again.", "Down to the wire, then back."), says what its aura was for in words, and shows its fuse in bars like Battery's level chart: zoomed to the session's own hours, 0 % always and 125 % only once it got there, grey down to 85 % so a calm session reads calm, green above 100 %, orange as it burns and red in the last third. When you were cool shows like Battery's charging: a light overlay on the bars and a line under the axis, with one symbol on the longest. No emoji or glitter on the chart: where it blew shows in the bars.
- **Principle:** The peak-end rule, and recognition over recall: the shape is the story, and a familiar chart reads at a glance. The words and the bars use the same thresholds, so they never disagree.
- **Evidence:** strong for peak-end; craft for the chart.
- **Tried:** a step line with clock ticks (too sharp, read like a report); a soft line with embers, ash and twinkles (juice with no purpose); the reason for the aura on hover only (hidden, and it moved the layout); the whole day on the axis (a short session shrank to a few bars).
- **Source:** [Kahneman et al. 1993](https://doi.org/10.1111/j.1467-9280.1993.tb00589.x)

## peak-end
- **Rule:** A session's line is built from facts only and ends on the recovery when there is one: "Boomed at 14:12. Cooled off by 14:40."
- **Principle:** The peak-end rule. We remember an experience by its peak and its end: most people chose to repeat a longer cold-water trial because it ended slightly warmer.
- **Evidence:** strong, though in a meta-analysis the plain average predicted about as well.
- **Source:** [Kahneman et al. 1993](https://doi.org/10.1111/j.1467-9280.1993.tb00589.x)

## fresh-start
- **Rule:** Every session gets a fresh stick, when it closes after 30 quiet minutes. Aura starts at zero each day, and the League table each Monday.
- **Principle:** New periods motivate. Gym visits rise after new weeks, months and birthdays.
- **Evidence:** mixed.
- **Source:** [Dai, Milkman & Riis 2014](https://faculty.wharton.upenn.edu/wp-content/uploads/2014/06/Dai_Fresh_Start_2014_Mgmt_Sci.pdf)

## rare-booms
- **Rule:** The fuse is a thermostat: +0.75 per Boom, −0.25 per calm workday (a local day with prompts and no Boom), never below 1, aiming at 1–2 Booms per person a week.
- **Principle:** Habituation. Repeats lose their punch, so a rare bang stays fresh. Don't fight habituation with volume.
- **Evidence:** strong. Tuned on a replay of 13 weeks of one player's real prompts. Shrinking per calm session ran at 3.5–4.75 Booms a week over the hot last month, 2–3× the target, since the calm sessions between hot ones shrank it right back. Per calm workday it lands at 1.5 a week over that month, with no week above 2, and at 2 or less with twice the prompts or 25% more heat. Three calm workdays undo a Boom. For calm players the minimum fuse sets the rate, whatever the thermostat.
- **Source:** [Rankin et al. 2009](https://doi.org/10.1016/j.nlm.2008.09.012)

## aura-not-work
- **Rule:** Aura never tracks how much you work. A session earns one award, the best thing that happened: a roast 8, a close call 3, or a cool session 1, and only one cool session a day earns its point. A cool session earns the same at 5 prompts or 500, cool counts per session and not per prompt, nothing pays per Boom, and sessions and their lengths never leave the Mac.
- **Principle:** Overjustification. Across 128 studies, expected tangible rewards lowered free-choice interest, while positive feedback raised it. Points per prompt or per hour would also turn Lunte into a work tracker, something a boss could use.
- **Evidence:** mixed: its breadth is disputed. Tuned on a replay of 13 weeks of one player's real prompts. Worth 1, 2 and 5 with no daily cap, cool sessions made 67% of aura, and daily aura tracked prompts per day at r = 0.75: a work tracker. At 1 once a day, 3 and 8, that falls to r = 0.49, near the floor of about 0.45 that aura from heat alone has, since more prompts give more chances. Its sources split 39% cool, 29% close calls and 32% roasts if half the Booms are roasted, and no source passes half at a quarter or three quarters.
- **Source:** [Deci, Koestner & Ryan 1999](https://depts.washington.edu/techdocs/papers/deciExtrinsicRewardsAndIntrinsicMotivation99.pdf)

## silent-pings
- **Rule:** When someone Booms, the Club gets a silent ping without the name. The Boom is the only sound in the room, and nobody is ever outed.
- **Principle:** Benign violation. Humour needs something that seems wrong but is safe. Losing it at a machine, anonymously, is safe; naming someone isn't, and a ping sound would out the Boomer, whose Mac is the only one that stays quiet.
- **Evidence:** mixed: the best working test of humour, partly supported.
- **Source:** [McGraw & Warren 2010](https://doi.org/10.1177/0956797610376073)

## never-fake-reactions
- **Rule:** Every reaction comes from a real person. Lunte never fakes a reaction, a near-miss, progress or a number.
- **Principle:** Dark game patterns are designs that work against players' interests without their consent, and engineered near-misses are a gambling technique.
- **Evidence:** weak: an ethics framework, not an experiment. It's a line, not a knob.
- **Source:** [Zagal, Björk & Lewis 2013](https://research.chalmers.se/en/publication/177148)

## no-streaks
- **Rule:** No streaks: nothing to keep alive, nothing to break, and no nudges to come back.
- **Principle:** A broken streak lowers later engagement, more so when people blame themselves, and nudges to recover mostly don't help.
- **Evidence:** mixed: field data and experiments, from one paper.
- **Source:** [Silverman & Barasch 2023](https://doi.org/10.1093/jcr/ucac029)

## whole-session-dots
- **Rule:** The popover's dots cover the whole open session, not just the last 30 minutes. Past eight rows the dots scroll, newest at the bottom with a fade at the top, so a long session never grows the popover past them.
- **Principle:** Persistence. Game feel leaves traces, such as skid marks, trails and debris, that encode the past in what's on screen now, so you can rebuild what happened after you missed it.
- **Evidence:** weak: craft knowledge, collected in a survey.
- **Source:** [Pichlmair & Johansen 2020](https://arxiv.org/abs/2011.09201)

## quiet-boom
- **Rule:** After the bang the menu bar has no fire: an SF Symbol and a word, in the menu bar's own colour and font. First the tier's name, for at least 5 s, then "Still burning" while the heat keeps coming, or "Calmed down" 10 minutes after the Boom or its last step up, until the fresh stick. Escalating and calming down only swap the words, with a little spring, and they're still in between. The popover still says you're blown.
- **Principle:** Calm technology. A tool should live in the periphery and move to the centre only when it matters. You stay blown until 30 quiet minutes, often well over an hour, and a Boom that shouts all that time is noise in the corner of your eye. Keeping colour for the fuse also makes its red and green worth more.
- **Evidence:** weak: a design frame, not an experiment.
- **Tried:** red text; a big BOOM that stayed; a new blast for each tier; words that moved all the time. Each one kept shouting for the whole blown hour.
- **Source:** [Weiser & Brown 1995](https://calmtech.com/papers/designing-calm-technology)

## just-the-fuse
- **Rule:** The menu bar item is a fuse and nothing else: one line in three coils, fixed at its start on the left, a little uneven. Like a spring, the coils sit tight when there's plenty left and spread as it runs out, so you can tell the length from the shape at a glance. No stick, no numbers, no cartoon.
- **Principle:** Character from physics. Motion that follows physical rules, such as springs, easing and squash and stretch, reads as alive and makes a thing feel like an object rather than a picture.
- **Evidence:** weak: craft.
- **Tried:** a dynamite stick with cartoon bursts, which looked like clip art; more coils as the fuse grows back (it stays three and squeezes tighter instead); perfectly even coils.
- **Source:** [Pichlmair & Johansen 2020](https://arxiv.org/abs/2011.09201)

## still-between-prompts
- **Rule:** The fuse moves only when a prompt does something. While the model rates a prompt, a faint breeze runs through the coils. Then the result shows at once: nothing, a burn, new fuse, or both. A burn's flame burns on for a few seconds, longer the nearer the end, and goes out in a puff. In between, it's still.
- **Principle:** Motion that starts grabs attention, so motion in the corner of your eye should mean something just happened. A fuse that always moves teaches you to ignore it. The breeze answers you at once ([two-clocks](#two-clocks)) without giving the verdict away.
- **Evidence:** strong that the onset of motion captures attention. The breeze and the flame's timing are craft.
- **Tried:** a flame that burnt all the time.
- **Source:** [Abrams & Christ 2003](https://pubmed.ncbi.nlm.nih.gov/12930472/)

## burn-tip-feed-start
- **Rule:** Heat burns from the tip, right to left, in fire colours. Cool feeds new fuse in at the start, from the left, in green. A prompt that's hot and cool at once does both, and you see both.
- **Principle:** A clear link from act to outcome. Amplification that blurred that link lowered players' motivation, so each cause gets its own end of the fuse.
- **Evidence:** mixed.
- **Source:** [Kao et al. 2024](https://spiral.imperial.ac.uk/entities/publication/253c32f5-d124-4a23-88b5-9aaaf114608d)

## close-call-crawl
- **Rule:** A burn into the last third slows to a crawl that stalls and starts again, each stall its own length and silent, and the flame drips: burning drops fall slowly from it, swaying and cooling, more the nearer the end, until the flame goes out or cool comes in. The Boom starts exactly the same way, so until the end you can't tell which it is. The crawl and the drops only ever show the real fuse ([never-fake-reactions](#never-fake-reactions)).
- **Principle:** Curiosity is the gap between what you know and what you want to know, and suspense lives in the doubt. Curiosity drove enjoyment more than anything else in the 1,699-player juice study.
- **Evidence:** mixed.
- **Tried:** a Boom you could see coming: the fuse just ran out, so there was no doubt left. Dimming the whole screen, darker nearer the end: it read as suspense, but it was annoying, since it took over the screen for a moment that mostly turns out fine. The drops stay by the fuse.
- **Source:** [Loewenstein 1994](https://doi.org/10.1037/0033-2909.116.1.75)

## boom-in-the-stillness
- **Rule:** The Boom's own burn crawls and stalls like a close call, sound and all, then races to the end, fastest last, in 2.8 s, showering drops that drift down and go out, its sizzle loudest and highest at the very end, and cuts out. Then 1–3 s of stillness ([two-clocks](#two-clocks)), and it blows into it: a flash, then time starts from a near stop and eases back up over 0.9 s while the blast opens out, with real but faint smoke. Then just the symbol and the word ([quiet-boom](#quiet-boom)). It's the one loud moment, so it's big, but the fire stays near the menu bar and only sparks fall further.
- **Principle:** Hitstop and anticipation. A freeze on impact gives the eye time to feel the weight, and a wind-up points attention at what's coming.
- **Evidence:** weak: craft.
- **Tried:** a red tint, which read as an alarm; the screen going dark under the menu bar for the race and the silence, which read as suspense but blacked out the whole screen and was annoying; a comic "BOOM!" word on screen; a wait of up to a minute, then up to 12 s, which felt like waiting rather than suspense, then 1–6 s; a silent race, which left no build-up for the silence to hold; a race that only sped up, 1.6 s, which built less suspense than a close call's crawl; thick smoke; sparks that started as long streaks in the slow motion, a cartoon starburst (the motion blur is a real moment's worth, so in the stillness they're crisp, as on slow-motion film); Core Animation's emitters, round dots that couldn't streak and couldn't be rendered to look at frame by frame.
- **Source:** [Sakurai on hitstop](https://sourcegaming.info/2015/11/11/thoughts-on-hitstop-sakurais-famitsu-column-vol-490-1/) (fan translation)

## every-boom-its-own
- **Rule:** Each Boom blows its own way: a kaboom at 0.8 to 1.25 of its size, its sparks and its fire's turbulence its own, all picked from the Boom's id, never from its heat, its tier or anything else you did. A bigger one sounds a little deeper, never louder. A kind is only a recipe, so a new look later, such as a skin, is a new recipe; four more wait for that.
- **Principle:** Habituation is stimulus-specific. A repeated stimulus loses its punch, and a changed one brings the response back, so variety in flavour keeps a rare bang fresh without turning it up. Picking by id means more anger never buys a bigger show ([one-boom-per-session](#one-boom-per-session)).
- **Evidence:** strong for habituation and its stimulus specificity. The kinds, their sizes and the juice they spend are craft, tuned by eye on rendered frames (`scripts/render-fuse.sh blast`).
- **Tried:** five kinds picked at random, a burst, a crackle, a gold willow, a ring and the kaboom. The kaboom, with its sound, was the clear favourite, so for now every Boom is one, and the others are kept as recipes for skins.
- **Source:** [Rankin et al. 2009](https://doi.org/10.1016/j.nlm.2008.09.012)

## fuse-sounds-opt-in
- **Rule:** The Boom is the only sound until you ask for more. Sound effects in Settings, at one volume: Minimal, the default, is the Boom alone, its build-up as the fuse races out, the silence and the bang. Medium adds the flame, one cartoon dynamite fuse for all it does: it catches with a flare, sizzles while the tip burns along and falls silent when it stalls, quiet on a long fuse and louder, higher and crackly near the end as it crawls and drips, and goes out in a comically short puff. Maximum adds cool growing it back and a fresh fuse, and plays the flame a little louder. Every fuse sound is pitched by how much fuse is left, like a string: the shorter, the higher, up to 1.8 times near the very end, so you hear the end coming without looking. All of it sits far under the bang, and sending a prompt, or one that does nothing, never makes a sound.
- **Principle:** A burn heard at once points straight at you, the very link the Boom's delay and the Club's silent pings are there to break ([two-clocks](#two-clocks), [silent-pings](#silent-pings)), and juice follows an inverted U, so most prompts stay silent ([juice-inverted-u](#juice-inverted-u)). Alone at your desk, the trade can be worth it, so it's yours to make. The Boom's build-up starts about a second after your prompt, but the 1–3 s of silence still stands between it and the bang. Higher pitch reads as more urgent, one of the steadiest findings on warning sounds, and a shorter string sounding higher is the physics the fuse already plays by ([just-the-fuse](#just-the-fuse)). A sound for every prompt sent could be instant, since the hook reaches the app in about 15 ms, but most prompts do nothing, and a sound on hundreds a day would wear off and get the sound turned off for good, so the breeze answers a send instead.
- **Evidence:** mixed, from the entries it leans on; strong that pitch carries urgency. The levels, the voice and the curve are craft, tuned by ear on `scripts/render-fuse.sh tour` and in the Boom Lab.
- **Tried:** a sound of its own for each move, from separate recordings (a burn, a sizzle under the drops, a puff as it goes out): they didn't hang together, and a close call didn't sound like the burn it came from. One synthesised voice, noise shaped by the scene: it hung together, but sounded like static. A real fuse cut into a catch, a calm and a hot loop: real, but not satisfying to listen to. Eight cartoon dynamite fuses side by side (`scripts/render-fuse.sh fuses`): the seventh, a sparkler-like crisp crackle, won, the fifth and eighth after it; it's one loop, played faster and higher as the scene says. A note under the slider that people near you hear a burn. Two sliders, Boom and Fuse.
- **Source:** [Kao 2020](https://doi.org/10.1016/j.entcom.2020.100359) · [Edworthy, Loxley & Dennis 1991](https://doi.org/10.1177/001872089103300206)

## summary-next-open
- **Rule:** When a session closes, it waits in Today with its name, its aura, and a blue dot until you open it, there when you next look; opened, it tells its story (see [session-story](#session-story)). Nothing pops up when a session closes, and the top of the popover is only ever the session you're in.
- **Principle:** The peak-end rule. We remember an experience by its peak and its end, so the story ends on the recovery and what it earned. A session closes after you've left, so its story is a memory device, there when you next look.
- **Tried:** a last-session card pinned at the top the first time the popover opened after a session (awkward, and it pushed the live session away).
- **Evidence:** strong, though in a meta-analysis the plain average predicted about as well.
- **Source:** [Kahneman et al. 1993](https://doi.org/10.1111/j.1467-9280.1993.tb00589.x)

## history-not-a-score
- **Rule:** Today lists today's sessions, and Previously the ones before, by day, each as its own fuse, its name and its aura, and opens any one's story under it. It's read from the log on this Mac and never sent. It never adds up how long you worked, and never ranks sessions.
- **Principle:** Being watched doesn't help. Across 94 samples, electronic performance monitoring didn't improve performance and went with more stress. Hours added up would turn Lunte into a work monitor, for you or for a boss.
- **Evidence:** mixed: a meta-analysis, with small effects that vary with how the monitoring is done.
- **Source:** [Ravid et al. 2023](https://doi.org/10.1111/peps.12514)
