# God Bot Record

The bot's results and what each change was meant to do to them, in one place.

Keep it cheap: one row per match, one row per change that was meant to move the needle.
The raw data behind a row is the archived run in `runs/` (`scripts/archive_run.py`), and the
behaviour itself is the commit in the first column — this file is a summary, not a second
`git log`.

## Results

| Date | Commit | Map | Opponent | Result | Length | Notes |
|---|---|---|---|---|---|---|
| 2026-10-18 | pre-`6f7530a` | mirage | chairon / Balanced / Odin | win | 26:25 | Raids aborted on contact, own Titan attacks recalled, push/slow cadence thrashed |

## Behaviour changes

| Commit | Change | Expected effect | Observed |
|---|---|---|---|
| `f806577` | Warship monitor destroys its query and skips dead units | No query warnings or failed deletes on a non-naval map | — |
| `351a752` | Raids pick the least-defended drop site and are judged on the troops on the target | Raids land instead of aborting within seconds | — |
| `91bc1e9` | A defend flicker no longer ends a push; push reads the enemy army to decide it outguns it | A stable 90s cadence once ahead, instead of thrashing to 1350s | — |

Fill in **Observed** after the next match; if a change did not help, say so here and revert
it or retune it rather than leaving the row silent.
