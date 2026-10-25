# Why the rules are what they are

One entry per game rule: the rule, the principle behind it, how strong the evidence is, and one public source. The code points here with `// Why:` comments, and the tests that guard a rule are named after it, so a change that drifts from the reason trips one. Change a rule's entry here before you change the rule.

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
- **Rule:** The player's own feedback is instant: within 0.1 s, 1 s at worst. The room's Boom waits a random 5–60 s.
- **Principle:** Perceived causality. People see "that made that happen" only when the effect follows at once, and even a 160 ms stagger cut causal ratings by about a third. Instant keeps the player's sense of agency; the delay breaks the room's link to the culprit.
- **Evidence:** strong for the effect, mixed on the exact window.
- **Source:** [White 2017](https://doi.org/10.1007/s00426-017-0853-y)

## juice-inverted-u
- **Rule:** Most prompts stay silent. The menu bar's small juice budget goes on a few moments: the Boom, the roast and the close call.
- **Principle:** Juice follows an inverted U. Medium and high juice beat both none and extreme on experience, motivation and play time (Kao 2020), and in a pre-registered study of 1,699 players, amplification that blurred the link from action to outcome lowered motivation (Kao et al. 2024).
- **Evidence:** mixed.
- **Source:** [Kao 2020](https://doi.org/10.1016/j.entcom.2020.100359)

## prepulse-fizz
- **Rule:** A short fizz comes just before the bang.
- **Principle:** Prepulse inhibition. A faint sound 30–500 ms before a loud one dampens the startle reflex, so the bang stays a cartoon, not an alarm.
- **Evidence:** strong in the lab. The fizz is an application of it, untested.
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
- **Rule:** Cool grows the fuse back. A cool prompt mends some of what's burning, never below zero, and a prompt that's hot and cool at once, roasting your agent live, burns less than the heat alone.
- **Principle:** Humour as reappraisal. Good-natured humour lowered negative feeling more than mean humour did. Lunte rewards what you do with the anger, not the anger.
- **Evidence:** mixed: small samples.
- **Source:** [Samson & Gross 2012](https://doi.org/10.1080/02699931.2011.585069)

## close-call
- **Rule:** When the fuse gets into its last third and climbs back out without a Boom, that's a close call: one per dip, credited the moment it climbs out, and worth aura. Exactly a third left counts, whatever the floating point says. It's never faked, and the fuse is never shown closer than it was.
- **Principle:** Competence and relief. "I held it together" feeds competence, one of the needs that predicts enjoyment, and a reward works best right after the act.
- **Evidence:** strong for competence, mostly correlational. Tuned on a replay of 13 weeks of one player's real prompts: the last third gives 1.3 close calls a week (2 in the hot last month), about 1.3 per Boom, rare enough to mean something and common enough to happen. The last quarter gave 0.9 a week, and the last half 3.2, which is too cheap.
- **Source:** [Ryan, Rigby & Przybylski 2006](https://doi.org/10.1007/s11031-006-9051-8)

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
- **Rule:** Aura never tracks how much you work. A cool session earns the same point at 5 prompts or 500, cool counts per session and not per prompt, nothing pays per Boom, and sessions and their lengths never leave the Mac.
- **Principle:** Overjustification. Across 128 studies, expected tangible rewards lowered free-choice interest, while positive feedback raised it. Points per prompt or per hour would also turn Lunte into a work tracker, something a boss could use.
- **Evidence:** mixed: its breadth is disputed.
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
