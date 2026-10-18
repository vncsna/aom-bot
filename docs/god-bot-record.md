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
| 2026-10-18 | pre-`6f7530a` | mirage | chairon / Balanced / Odin | win | 26:25 | Raids aborted on contact, own Titan attacks recalled, push/slow cadence thrashed |
| 2026-10-18 | `688a149` | mirage | chairon / Defender / Demeter | win | 21:31 | Ground the enemy down base by base, but all four raids aborted and the push cadence flapped until 14:54 |

## Behaviour changes

| Commit | Change | Expected effect | Observed |
|---|---|---|---|
| `f806577` | Warship monitor destroys its query and skips dead units | No query warnings or failed deletes on a non-naval map | Clean — no query-name or failed-delete warnings. A warship is still trained and scrapped twice (10:00, 16:30) on a non-naval map, so the leak is upstream of this monitor |
| `351a752` | Raids pick the least-defended drop site and are judged on the troops on the target | Raids land instead of aborting within seconds | No effect — all four raids aborted (12 of 16 lost; then 18, 15 and 25 enemies vs our 8, 8 and 5). Raid parties stay ~8 pop, and two raids reused the same target point |
| `91bc1e9` | A defend flicker no longer ends a push; push reads the enemy army to decide it outguns it | A stable 90s cadence once ahead, instead of thrashing to 1350s | Partial — no 1350s thrash, but push and slow still flip: push 09:30 → slow 10:27; push 13:48 → slow 14:48 → push 14:54. The 90s interval then held to the end |

Fill in **Observed** after the next match; if a change did not help, say so here and revert
it or retune it rather than leaving the row silent.
