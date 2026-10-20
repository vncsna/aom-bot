# God Bot Design

How the God Bot in `game/ai/god_bot.xs` is put together and why. Background on how bot
behaviour is expressed lives in [`ai-architecture.md`](ai-architecture.md).

## Goal

**Always win.** The bot plays every match to win — 1v1 and team games alike — and it is
expected to win by using powers a human player does not have. A loss is a bug to be
diagnosed from the telemetry, not an acceptable outcome of a fair game.

## Bot powers

The player sees a fogged map and acts on scouted information. The bot is not held to that.
It reads the game state directly through the knowledge base, so everything below is known
the moment it matters, with no scout and no guess:

- **The enemy's army, anywhere.** `godEnemyMilitaryNear()` counts the enemy's land military
  around any point, and `kbUnitCount()` gives the enemy's army size, age, town centres and
  villager count.
- **The enemy's Titan.** `godEnemyTitanID()` and `godTitanNear()` locate it without seeing
  it, so the army never walks into one.
- **The attack's own strength.** `kbUnitsGetPower()` measures the army's combat power
  exactly, rather than estimating from unit counts.

These are the deliberate cheats. Anything a human could do — building, spending, training,
attacking — the bot does the same way, through the engine's plans; it is handed no free
resources and no instant builds. Its edge is that it never has to look.

## Approach

The bot is a Conqueror at heart: slow, territorial, economy-heavy. It has **four
responsibilities**, each with one implementation:

1. **Economy** — the engine's auto-eco, a large villager cap, and chosen minor gods.
2. **Defence** — the engine's `gPrimaryLandDefendPlan` and `towerManager`, untouched.
3. **Offence** — the engine's `attackManager` on a deliberately slow cadence, a decisive
   push when ahead, and a refusal to feed a Titan.
4. **Endgame** — the engine's Titan and Wonder monitors, with the two stalls it leaves
   behind (the favour sink, a failed Wonder placement) patched.

The land army has **one owner**: the engine's primary defend plan. No custom plan claims
it. Earlier versions added a choke plan, a fallback plan, a per-base threat count, an ally
assist, raids and a front tower on top; they competed with each other and with the engine,
and a plan ordered to an unreachable point froze the army in place. See the
[complexity budget](../AGENTS.md#complexity-budget) before adding another.

## Identity

`GodBot.personality` is purely cosmetic — it points the skirmish lobby name, tooltip and
portrait at the Conqueror strings. Behaviour is not driven by the personality at all: per
the official `How-to create your own skirmish AI.pdf`, the name in `personalities_mods.xml`
generates the script constant (`GodBot` → `cPersonalityGodBot`), so we can never satisfy
`cPersonalityCurrent == cPersonalityConqueror`. Because the bot replaces the strategy system
with `setOverrideStrategy`, the Conqueror tuning is implemented directly instead. The
generated index also makes the stock name lookup warn at startup (`Unknown
cPersonalityCurrent.`); that is harmless unless `aiDebugScript` is on, where the warning
becomes a debugger breakpoint that freezes the bot — see the AI Debugger Config section in
[`AGENTS.md`](../AGENTS.md).

## Architecture

- `preInit()` sets the economy target and the minor-god picks, then installs the override
  strategy. The stock strategies are never added.
- The strategy enables every engine flag, applies our policy (naval off, slow cadence), and
  runs once a second for the few things that must react to the live game: the age change
  and the attack gate.
- Monitors handle everything periodic. They are enabled in `postInit()`.

| Piece | Where | Job |
|---|---|---|
| Strategy | `godBotStrategy()` | Flags, naval, cadence, attack gate |
| `godNavalCleanupMonitor` | 30s | Scrap warships on non-naval maps |
| `godTowerUpgradeMonitor` | 10s | Research tower upgrades as early as possible |
| `godPushMonitor` | 10s | Decide the push and change the cadence |
| `godRetreatMonitor` | 10s | Pull an attack back when it is bleeding out, outnumbered or facing a Titan |
| `godFavourReserveMonitor` | 10s | Hold the 50 favour for Secrets of the Titans once the bank is ready |
| `godWonderFallbackMonitor` | 20s | Move a failed Wonder plan to the next TC base |
| `godTelemetryMonitor` | 30s | Recount the players and emit a `[GBOT]` metrics line |

## Behaviour

### Economy and expansion

**A real boom.** `preInit()` sets `gOverrideMaxVillagerPop` so the engine's auto-eco
maintains a large villager count. Conqueror is eco-heavy; the villager mass is what funds a
slow push.

**Minor gods are chosen, not rolled.** The engine picks the Classical/Heroic/Mythic minor
god at random. We set `gOverrideClassicalMinorGod` / `gOverrideHeroicMinorGod` /
`gOverrideMythicMinorGod` per major god, favouring economy, defence and late-game upgrades.
The picks and the matchups behind them are in
[`god-bot-minor-gods.md`](god-bot-minor-gods.md).

### Defence

**The engine owns it.** `gPrimaryLandDefendPlan` decides where the army goes and
`towerManager` decides how many towers a base gets. There is no per-base threat
calculation, no stance machine and no tower override: the engine already computes enemy
power per defend base in `military_defend.xs` (`gEnemyPowerInBases`) and moves its primary
defend plan to the attacked base. A defend-home flag was tried and flipped ten times in a
match without changing the outcome, so it is gone; the attack gate no longer closes for it.

**Turrets are upgraded immediately.** `godTowerUpgradeMonitor` researches the next
obtainable tower upgrade as soon as we own a tower, ignoring the stock time gates (4 minutes
in Classical, 5 in Heroic, 6 in Mythic). It follows the engine's own progression and culture
variants, publishes the plan through `gTowerOffensiveResearchPlanID`, and reuses the stock
`resetOffensiveTowerResearchPlan` handler so the stock monitor defers instead of stacking a
second plan.

### Navy

Naval military only exists on a map that is really naval: an island map, or one where we
start on a transport. Everywhere else the naval flags are cleared,
`gOverrideNavalMaxMilitaryPop` is pinned to 0, and `godNavalCleanupMonitor` deletes any
warship that slips through, naming the unit it deletes so a leak can be traced back to its
source. The policy is re-applied at every age change, not only at init, because the engine
re-enables its default flags as the game goes on. Fishing and Docks are untouched — this is
about warships only.

### Offence

**A slow rhythm the bot holds itself.** Conqueror's attack interval is multiplied by
`cGodCadenceMultiplier` (1.5) and re-applied on every age change and cadence change. Setting
the interval is not enough on its own: the engine's `attackManager` randomises it on every
launch, and on Hard and above it skips the time check once the army is large or the
resources are in excess. So the bot drives `cStrategyFlagCanAttack` itself and opens it only
once its own interval has elapsed. The engine still decides what to attack and how; the
rhythm is ours.

**A decisive push once the bot knows it is ahead.** `godShouldPush()` fires when we are in
Heroic or later, have a real army (`cGodPushArmyPop`), and either we are an age ahead or we
outgun the enemy — read directly, not estimated — by `cGodPushAdvantagePercent`. The
comparison is on army power, not on a unit count, so a hero is not one slinger; and it is
asymmetric: committing takes the full margin, staying committed only takes
`cGodPushHoldPercent`, so a wobble around the threshold cannot flip the cadence back and
forth. While pushing the cadence drops to `cGodPushInterval`, so the army stays massed. The
push decision lives in `godPushMonitor` because it reads both armies.

**Retreat when it is not working.** `godRetreatMonitor` judges each attack in the field on
its own. The plan carries its own loss-window sample — the power it had and when the window
opened, as plan user variables — and the attack is pulled back when it loses
`cGodRetreatLossPercent` of that power within `cGodRetreatLossWindow` seconds, is clearly
outnumbered by the enemy on the spot, or stands in front of a Titan. The loss window
is what catches a fight the enemy count calls even while the army melts. Pulling back the
main army also sets the next attack one interval out, so the bot regroups rather than
re-committing. It leaves the engine's own Titan plans alone: a Titan is one unit, so the
outnumbered check would otherwise recall it on every pass and it would never land.

**Never feed a Titan.** A Titan is one unit, so the outnumbered check never sees it, and it
kills an army faster than any count notices. `godTitanNear` calls off any attack standing
within `cGodTitanFleeRadius` of one, and `godTitanAllowsAttack()` vetoes the attack gate
while an enemy Titan is alive and we cannot answer it: no Titan of our own and less than
`cGodTitanHuntArmyPop` military pop. The army waits at home with the towers and our own gate
instead of walking into it; once the army is big enough, or our own Titan is out, attacks
resume on their normal rhythm.

### Endgame

**The engine decides when.** `enableAllStrategyFlags()` turns on `cStrategyFlagBuildTitan`
and `cStrategyFlagBuildWonder` from init, and the bot keeps its hands off them. An earlier
version held both behind a 360-second Mythic stalemate; it fired in the three matches that
followed and none of them produced a Titan, while the last win had no latch at all and stock
AIs in those same matches got Gates up on the engine's own clock. The engine's guards are the
real ones: Mythic, 1500 excess of each resource, and 50 favour banked.

**The engine does the rest.** `secretsOfTheTitansMonitor` researches Secrets of the Titans,
`titanGateConstructionMonitor` places the Gate, and the engine's Wonder monitor builds the
Wonder. Two engine stalls are patched at their cause, both logged so the next run shows
whether they fired:

- **The favour reserve.** Myth training spends favour as fast as it arrives, so the bank
  never reaches the 50 the tech costs: in the 41-minute mirage loss favour peaked at 46 and
  the tech was refused for 17 minutes. `godFavourReserveMonitor` destroys the myth training
  plans and suspends `godPowerRebuyMonitor` once the engine's own bank check
  (`haveExcessResourceAmount(1500)`) passes, so the hold cannot start before the purchase is
  possible. Cancelling refunds the favour; it releases when the research starts or the Gate
  is charged, and the rest of the army keeps training throughout.
- **The Wonder fallback.** The engine offers the Wonder only the safest base's back areas and
  a failed plan stays failed, so a crowded base stalls it for the rest of the match. The
  Wonder costs 5,000 food, 5,000 wood and 5,000 gold and no favour, so it never competes with
  the tech. `godWonderFallbackMonitor` destroys the failed plan and rebuilds on the next TC
  base in the ring with the engine's own builder count, which searches the whole base
  instead of the back areas.

Neither one buys or places anything on its own: the win-condition flags are the engine's,
and both monitors return as soon as the Gate is charged or the Wonder exists.

## Telemetry

`godTelemetryMonitor` emits one line every 30s:

```
[GBOT] t=… age=… vills=… pop=cur/cap army=… food=… wood=… gold=… favor=… enemyAge=… enemyTitan=0|1 titans=… wonder=… state=hold|push underAttack=0|1 enemies=… allies=…
```

`state` is the push stance — `push` while the army is committed, `hold` otherwise.
`underAttack` is the engine's `gDefensivelyOverrun` flag, reported separately because the
push state does not change when a base is poked. `enemies`/`allies` are the live player
counts refreshed by the telemetry monitor.

It lands in the per-player AI log, `temp/Logs/MythRetoldAIOutputPlayer<N>.txt` (UTF-16).
`scripts/parse_ai_log.py` turns it into a per-run summary. This is the feedback loop that
turns the tuning constants from guesses into measurements; the log locations and the
run-metadata options are documented in [`../AGENTS.md`](../AGENTS.md). Results and what each
change was meant to do are summarised in [`god-bot-record.md`](god-bot-record.md).

## Tuning

| Constant | Meaning |
|---|---|
| `cGodCadenceMultiplier` | Extra slowdown on top of Conqueror's attack interval |
| `cGodMaxVillagerPop` | Villager count the economy targets |
| `cGodPushArmyPop` | Military pop required before we commit to a decisive push |
| `cGodPushInterval` | Seconds between attacks while pushing |
| `cGodPushAdvantagePercent` | How much bigger our army must be than the enemy's to push |
| `cGodPushHoldPercent` | How much bigger it must stay to keep pushing |
| `cGodRetreatLossPercent` | Share of an attack's power it can lose inside the window |
| `cGodRetreatLossWindow` | Seconds the loss is measured over |
| `cGodRetreatEnemyRatioPercent` | Enemy-to-us ratio at the attack that triggers a retreat |
| `cGodTitanFleeRadius` | How close an enemy Titan has to be to call an attack off |
| `cGodTitanHuntArmyPop` | Military pop needed to take an enemy Titan on |

## Caveats

- **`gDefensivelyOverrun` is the only defence signal.** The engine updates
  `gEnemyPowerInBases` and the flag on its own cadence (`defendManager`, 5s), so the bot
  reads those rather than running a second per-base calculation. The flag only gates the
  Wonder fallback now; the army needs no signal because the engine's own defend plan owns
  it. If a match needs a finer distinction than "overrun or not", add it here, not as
  another plan.
- **The army has no custom owner.** The engine's primary defend plan owns it. Any new plan
  must take it briefly and release it, or the complexity budget in
  [`AGENTS.md`](../AGENTS.md) must be raised deliberately.
- **The minor-god picks are a first pass.** They follow each god's documented focus, not
  measured results; revisit once telemetry shows which games are lost and why.
- **The tuning numbers are starting points.** Retreat and push thresholds are the first
  things to adjust after a game.
- **The endgame patches only touch the engine's stalls.** The favour reserve and the Wonder
  fallback both act on plans the engine already owns; neither creates a win condition of its
  own. A stall with a different cause (a missing bank, a Gate that cannot be placed) still
  belongs in `god-bot-record.md` before any new rule is added.
