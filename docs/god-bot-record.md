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
a branch those three cannot: a naval map for the naval-cleanup branch, a specific opponent,
or another major god for the minor-god picks.

Team games are their own coverage, because the team behaviour only runs there:

- **A 2v2:** exercises the assist plan — an ally base under pressure while our own bases
  are quiet.
- **A 3v3 on jotunheim** (the map of the last team-game loss): exercises defend-home, the
  front tower and the assist. Read `defend=`, `underAttack=` and `assist=` from the telemetry
  to see which fired.

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
| 2026-10-19 | `a8d272f` (tree) | jotunheim | 12-player FFA, chairon AIs | ? | 79:00 | The game that would not end. Stalemate latched at 35:34 and the bot asked for a Titan for the remaining 44 minutes; `titans=0` and `wonder=0` for all 155 samples. Titans were *not* disabled: three stock AIs in the same match researched Secrets of the Titans and had Gates up (players 2/3/5, 32:53–33:53). Our bot never got past the research: no `Researching Secrets of the Titans` line, and — the decisive one — no `Under attack - postponing the Titan Gate` line either, so the `titanGateConstructionMonitor` rule was never enabled, i.e. no Gate charge ever existed. From 38:00 to 48:00 it sat at 1.8–9.6k food / 3.9–18k wood / 1.5–2.9k gold in `normal` stance with `underAttack=0`, which clears every gate in `godBankCovers` except the 75 favour (50 × the 50% reserve) — favour is the one resource the telemetry line does not log. The Wonder could not cover for it: it is gated behind a live Titan, so 44 minutes of pop-capped grind, 33k wood banked and neither win-condition building placed |
| 2026-10-19 | `0c60d80` | jotunheim | larger team game (chairon AIs), Titan | loss | 52:18 | Loki (Norse). Boom to 91 vills / 210 pop; army peaked at 144 (26:12). The bot's team never led the score (own team ~50.8k vs enemy teams ~91.5k and ~81.8k), and it was under attack from 15:00 on. The stalemate Titan fired at 34:26 — 360s after Mythic at 28:26 — but no Titan ever appeared (`titans=0` all game) while it sat on a 2–6k wood bank. The enemy's Titan arrived at 35:13 and every raid and attack aborted on it (37:06, 40:49, 41:19, 42:20). From ~48:00 its bases were overrun, it lost its last TC at 50:53, and it resigned at 52:18 with healthScore 94 |
| 2026-10-19 | `f4ac062` | mirage | chairon / Balanced / Huitzilopochtli | win | ~34:30 | Ra. Push held almost unbroken from 17:30 (one hold at 27:32), but the bank grew past 30k from 23:00 on with army stuck near 140 at the 250 cap. Enemy reached Mythic at 18:00, no age deficit. The Titan only appeared at ~31:00, its Gate first logged at 27:29, and it was recalled 13 times in the 3.5 minutes it lived (8–23 enemies vs our 1, then the enemy Titan at 33:00), so it never landed |
| 2026-10-18 | `315a62f`–`c496020` | mirage | chairon / Conqueror / Odin | win | 26:31 | Enemy resigned with 7 power left, under attack in its bases from 10:02 to the end. Push/slow flipped 5 times, not 15. The gate never reopened after the 19:41 retreat, so the last 7 minutes were passive while the bank grew past 9k |
| 2026-10-18 | `a4e1d73` | mirage | chairon / Conqueror / Shennong | win | 26:31 | Enemy resigned. First run with the cavalry gold raid (`e747bea`). No raid landed; push/slow flapped 15 times in 20:52–23:04; the Wonder never started — blocked on gold excess, then on favour |
| 2026-10-18 | `688a149` | mirage | chairon / Defender / Demeter | win | 21:31 | Ground the enemy down base by base, but all four raids aborted and the push cadence flapped until 14:54 |
| 2026-10-18 | pre-`6f7530a` | mirage | chairon / Balanced / Odin | win | 26:25 | Raids aborted on contact, own Titan attacks recalled, push/slow cadence thrashed |

## Behaviour changes

| Date | Commit | Change | Expected effect | Observed |
|---|---|---|---|---|
| 2026-10-19 | `015519c` | Collapse the army to one owner: delete the choke, fallback and per-base threat count, replace the stances with one `gGodDefendHome` from `gDefensivelyOverrun`, merge the raids, delegate the Titan/Wonder to the engine, slow the cadence to 1.2x | The army cannot freeze on an unreachable choke or shuttle between a forward base and the capital; it attacks on a slow but finite rhythm; the engine's own Titan path is used | — |
| 2026-10-19 | `96368b4` | Count the live enemies and allies and log the game shape (`enemies=`, `allies=`, `stance=`) | A team game is distinguishable from a 1v1 in the telemetry, and the 1v1 baseline is unchanged | — |
| 2026-10-19 | `0ba0408` | Read enemy power on every Town Center base, split by player (`threat=`, `threatPlayers=`) | "Three raids from three players" reads as three players on our bases, not one global flag | — |
| 2026-10-19 | `1ab1d3f` | A fortify stance: no raids, no push, no Wonder/Titan, and `cGodFortifyTowersPerBase` towers per base while two or more players press us | The army stops dying in the open and the tower count rises above the engine's 2-3 | — |
| 2026-10-19 | `520c992` | Fall back to our most defensible base when the enemy on a base outguns the army there; runs in every stance | A losing fight moves under the towers instead of dying in the open | — |
| 2026-10-19 | `b9bfc78` | Assist an ally whose base is being overrun, with a capped share of the army, while our own bases are quiet | An ally is kept alive instead of leaving us facing all the enemies alone | — |
| 2026-10-19 | `07290ea` | Build a tower toward the enemy's centroid at the worst-hit base while fortifying | The threatened approach is covered, not just a random ring around the TC | — |
| 2026-10-19 | `b0072d2` | Hold the choke between us and the attacking enemy while fortifying | The fight happens on narrow ground instead of inside the economy | — |
| 2026-10-19 | `7cf3eaa` | A Mythic stalemate buys Secrets of the Titans from the bank, and the Wonder waits until the first Titan is out | The Titan arrives on the stalemate clock instead of whenever the engine's surplus check passes, and the army keeps the resources until then | The trigger works: it fired at 34:26, 360s after reaching Mythic at 28:26. But no Titan came out — `titans=0` for the whole match, with a 2–6k wood bank sitting unspent for the 18 minutes that followed. The bot's own log has no line for the purchase, so the failure is past the stalemate clock (the Gate or the research never completed). Reproduced on `a8d272f` (79:00, jotunheim): still no research line, and no gate-postponed line either, so no charge was ever granted; the only gate the telemetry cannot account for is favour. The line still cannot say which guard bit — favour is not in the telemetry and the guard itself is not logged |
| 2026-10-19 | `83c9130` | The retreat monitor leaves the engine's own Titan plans alone | The Titan is not recalled every ten seconds, so it reaches a base instead of standing idle | Not exercised — the bot never got a Titan of its own out (see the row above). Every Titan-driven retreat in this run was the bot pulling back from the enemy's Titan (37:06, 40:49, 41:19, 42:20) |
| 2026-10-18 | `514db6f` | A retreat regroups on the interval of the state the bot is in, not always the slow one | A retreat during a push re-commits on the fast interval, instead of sitting idle at pop cap for a whole slow interval | — |
| 2026-10-18 | `c496020` | A retreat sets the regroup interval to the slow rhythm explicitly | A retreat during a push buys a full slow interval, instead of re-committing on the 90s cadence | Worked, and overcorrected: the 19:41 retreat set the interval to the 450s slow rhythm while the push state stayed true, so the gate never reopened before the enemy resigned — 7 passive minutes at pop cap with a 9k bank. A dedicated, shorter regroup constant, or the push interval while still pushing, would keep the regroup deliberate without the dead time. Retuned in `514db6f` |
| 2026-10-18 | `c274af6` | The push is decided on army power, with an asymmetric margin (150% to commit, 110% to hold) | The cadence stops flipping; a push survives a wobble around the threshold | Held. 5 push/slow transitions in 26 minutes (09:40, 11:30, 11:54, 18:18, 18:49) against 15 in two minutes before, and the 19:41 retreat — 44 of 80 pop lost — did not flip the cadence |
| 2026-10-18 | `315a62f` | The bot drives `cStrategyFlagCanAttack` and opens it only once its own interval has elapsed | The slow rhythm holds at Hard and above, instead of the engine skipping its time check whenever the army is large or resources are in excess | Cannot be confirmed from the bot's log: the engine's attack-launch line lands in the other player's log and the archive keeps only the bot's own lines. No regression — the enemy reported being under attack from 10:02 to 26:04 and finished with 7 power |
| 2026-10-18 | `a4e1d73` | Naval policy re-applied on every age change, and a leaked warship named in the log | No warship on a non-naval map, or the leak named so it can be traced | Re-apply fired at each age change (03:31, 09:32, 19:20) and the names worked, but two warships still leaked — both the Dock's Egyptian myth unit: `Leviathan#1311517` at 10:00 (Classical) and `WarTurtle#1311907` at 19:30 (Mythic). The naval flags do not cover Dock myth training. Repeated next run: `Leviathan` at 10:00 and `WarTurtle` at 16:30, both at age changes |
| 2026-10-18 | `e747bea` | Cavalry raid on the enemy gold; a drop site with a guard is skipped | A fast party reaches the miners and leaves before the army answers | Ran twice (20:00, 24:00), both at the same mine (35, 7), both called off before landing ("1 enemy closed in", then "10 enemies closed in"). The foot raid still aborts every time: 11 vs our 5, 11 vs our 1, 15 vs our 2 |
| 2026-10-18 | `91bc1e9` | A defend flicker no longer ends a push; push reads the enemy army to decide it outguns it | A stable 90s cadence once ahead, instead of thrashing to 1350s | Partial — no 1350s thrash, but push and slow still flip: push 09:30 → slow 10:27; push 13:48 → slow 14:48 → push 14:54. The 90s interval then held to the end. Next run: it did not hold — 15 flips between 20:52 and 23:04, some a second apart, once the enemy army reached Mythic. The ratio test has no hysteresis |
| 2026-10-18 | `351a752` | Raids pick the least-defended drop site and are judged on the troops on the target | Raids land instead of aborting within seconds | No effect — all four raids aborted (12 of 16 lost; then 18, 15 and 25 enemies vs our 8, 8 and 5). Raid parties stay ~8 pop, and two raids reused the same target point |
| 2026-10-18 | `f806577` | Warship monitor destroys its query and skips dead units | No query warnings or failed deletes on a non-naval map | Clean — no query-name or failed-delete warnings. A warship is still trained and scrapped twice (10:00, 16:30) on a non-naval map, so the leak is upstream of this monitor |

Fill in **Observed** after the next match; if a change did not help, say so here and revert
it or retune it rather than leaving the row silent.
