# God Bot Record

The bot's results and what each change was meant to do to them, in one place.

Keep it cheap: one row per match, one row per change that was meant to move the needle.
The raw data behind a row is the archived run in `runs/` (`scripts/archive_run.py`), and the
behaviour itself is the commit in the first column — this file is a summary, not a second
`git log`.

## Which matches to run

The goal is "always win", so a **loss is the signal**, not a win rate — you are hunting
counterexamples. One match answers several questions at once: the bot's own `[GodBot]`
events (retreats, pushes, raids, tower upgrades, Titan handling) land in the archived run,
so read behaviour from the log rather than the result. Prefer a few matches that exercise
different branches over many repeats of the same one.

Hold a baseline fixed — one map, one difficulty, one opponent — so rows are comparable:

- **Baseline: every change.** One land map, one opponent (currently mirage / Balanced). The
  tripwire for a regression and the row comparable across commits.
- **An aggressive opponent** (e.g. Attacker or Overwhelmer). Exercises defence: the Wonder
  and Titan Gate hold under `gDefensivelyOverrun`, and the retreat logic.
- **A passive opponent** (e.g. Defender or Passive). Exercises offence: whether the bot
  closes a game the enemy will not leave, and whether the push/raid cadence presses.

That is three matches for a general read of the bot. Add another only when a change reaches
a branch those three cannot: a naval or tiny map for the naval-cleanup and tiny-map housing
branches, a specific opponent, or another major god for the minor-god picks.

Keep it small:

- Run the baseline on **every** change; re-run a coverage match only when you change what it
  exercises.
- **Repeat only when a match is borderline or lost** — that is when a win rate is worth
  measuring. Otherwise spend the run on an untried match instead of a repeat.
- On a **loss**, vary one axis at a time — opponent, then map, then god — to find what the
  bad case has in common.

## Results

| Date | Commit | Map | Opponent | Result | Length | Notes |
|---|---|---|---|---|---|---|
| 2026-10-18 | `315a62f`–`c496020` | mirage | chairon / Conqueror / Odin | win | 26:31 | Enemy resigned with 7 power left, under attack in its bases from 10:02 to the end. Push/slow flipped 5 times, not 15. The gate never reopened after the 19:41 retreat, so the last 7 minutes were passive while the bank grew past 9k |
| 2026-10-18 | `a4e1d73` | mirage | chairon / Conqueror / Shennong | win | 26:31 | Enemy resigned. First run with the cavalry gold raid (`e747bea`). No raid landed; push/slow flapped 15 times in 20:52–23:04; the Wonder never started — blocked on gold excess, then on favour |
| 2026-10-18 | `688a149` | mirage | chairon / Defender / Demeter | win | 21:31 | Ground the enemy down base by base, but all four raids aborted and the push cadence flapped until 14:54 |
| 2026-10-18 | pre-`6f7530a` | mirage | chairon / Balanced / Odin | win | 26:25 | Raids aborted on contact, own Titan attacks recalled, push/slow cadence thrashed |

## Behaviour changes

| Commit | Change | Expected effect | Observed |
|---|---|---|---|
| `514db6f` | A retreat regroups on the interval of the state the bot is in, not always the slow one | A retreat during a push re-commits on the fast interval, instead of sitting idle at pop cap for a whole slow interval | — |
| `c496020` | A retreat sets the regroup interval to the slow rhythm explicitly | A retreat during a push buys a full slow interval, instead of re-committing on the 90s cadence | Worked, and overcorrected: the 19:41 retreat set the interval to the 450s slow rhythm while the push state stayed true, so the gate never reopened before the enemy resigned — 7 passive minutes at pop cap with a 9k bank. A dedicated, shorter regroup constant, or the push interval while still pushing, would keep the regroup deliberate without the dead time. Retuned in `514db6f` |
| `c274af6` | The push is decided on army power, with an asymmetric margin (150% to commit, 110% to hold) | The cadence stops flipping; a push survives a wobble around the threshold | Held. 5 push/slow transitions in 26 minutes (09:40, 11:30, 11:54, 18:18, 18:49) against 15 in two minutes before, and the 19:41 retreat — 44 of 80 pop lost — did not flip the cadence |
| `315a62f` | The bot drives `cStrategyFlagCanAttack` and opens it only once its own interval has elapsed | The slow rhythm holds at Hard and above, instead of the engine skipping its time check whenever the army is large or resources are in excess | Cannot be confirmed from the bot's log: the engine's attack-launch line lands in the other player's log and the archive keeps only the bot's own lines. No regression — the enemy reported being under attack from 10:02 to 26:04 and finished with 7 power |
| `a4e1d73` | Naval policy re-applied on every age change, and a leaked warship named in the log | No warship on a non-naval map, or the leak named so it can be traced | Re-apply fired at each age change (03:31, 09:32, 19:20) and the names worked, but two warships still leaked — both the Dock's Egyptian myth unit: `Leviathan#1311517` at 10:00 (Classical) and `WarTurtle#1311907` at 19:30 (Mythic). The naval flags do not cover Dock myth training. Repeated next run: `Leviathan` at 10:00 and `WarTurtle` at 16:30, both at age changes |
| `e747bea` | Cavalry raid on the enemy gold; a drop site with a guard is skipped | A fast party reaches the miners and leaves before the army answers | Ran twice (20:00, 24:00), both at the same mine (35, 7), both called off before landing ("1 enemy closed in", then "10 enemies closed in"). The foot raid still aborts every time: 11 vs our 5, 11 vs our 1, 15 vs our 2 |
| `91bc1e9` | A defend flicker no longer ends a push; push reads the enemy army to decide it outguns it | A stable 90s cadence once ahead, instead of thrashing to 1350s | Partial — no 1350s thrash, but push and slow still flip: push 09:30 → slow 10:27; push 13:48 → slow 14:48 → push 14:54. The 90s interval then held to the end. Next run: it did not hold — 15 flips between 20:52 and 23:04, some a second apart, once the enemy army reached Mythic. The ratio test has no hysteresis |
| `351a752` | Raids pick the least-defended drop site and are judged on the troops on the target | Raids land instead of aborting within seconds | No effect — all four raids aborted (12 of 16 lost; then 18, 15 and 25 enemies vs our 8, 8 and 5). Raid parties stay ~8 pop, and two raids reused the same target point |
| `f806577` | Warship monitor destroys its query and skips dead units | No query warnings or failed deletes on a non-naval map | Clean — no query-name or failed-delete warnings. A warship is still trained and scrapped twice (10:00, 16:30) on a non-naval map, so the leak is upstream of this monitor |

Fill in **Observed** after the next match; if a change did not help, say so here and revert
it or retune it rather than leaving the row silent.
