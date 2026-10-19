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
- **The enemy's economy.** `godFindRaidTarget()` reads every enemy drop site's position and
  picks the one with the fewest troops on it.
- **The attack's own strength.** `kbUnitsGetPower()` measures the army's combat power
  exactly, rather than estimating from unit counts.

These are the deliberate cheats. Anything a human could do — building, spending, training,
attacking — the bot does the same way, through the engine's plans; it is handed no free
resources and no instant builds. Its edge is that it never has to look.

## Approach

The bot is a Conqueror at heart: slow, territorial, economy-heavy. It has **four
responsibilities**, each with one implementation:

1. **Economy** — the engine's auto-eco, a large villager cap, and chosen minor gods.
2. **Defence** — the engine's `gPrimaryLandDefendPlan`, towers raised while the base is
   overrun, and one ally assist.
3. **Offence** — the engine's `attackManager` on a deliberately slow cadence, a decisive
   push when ahead, raids on the enemy economy, and a refusal to feed a Titan.
4. **Endgame** — the engine's Titan and Wonder monitors, unlocked on a stalemate.

The land army has **one owner**: the engine's primary defend plan. The only custom plan
that may claim it is the transient ally assist. Earlier versions added a choke plan, a
fallback plan and a per-base threat count on top; they competed with each other and with
the engine, and a plan ordered to an unreachable point froze the army in place. See the
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
  runs once a second for the few things that must react to the live game: the age change,
  the defend signal, the stalemate, the win-condition flags and the attack gate.
- Monitors handle everything periodic. They are enabled in `postInit()`.

| Piece | Where | Job |
|---|---|---|
| Strategy | `godBotStrategy()` | Flags, naval, cadence, defend signal, stalemate, win conditions, attack gate |
| `godNavalCleanupMonitor` | 30s | Scrap warships on non-naval maps |
| `godPlayersMonitor` | 30s | Recount the enemies and allies still in the game |
| `godVillageMonitor` | 20s | One Temple + one military building per village |
| `godTowerUpgradeMonitor` | 10s | Research tower upgrades as early as possible |
| `godPushMonitor` | 10s | Decide the push and change the cadence |
| `godRetreatMonitor` | 10s | Pull an attack back when it is outnumbered or facing a Titan |
| `godAssistMonitor` | 10s | Send a capped share of the army to an ally about to lose a base |
| `godFrontTowerMonitor` | 30s | Nudge a tower toward the enemy while defending |
| `godRaidMonitor` | 60s | Hit the enemy economy with cavalry or a small foot party |
| `godTelemetryMonitor` | 30s | Emit a `[GBOT]` metrics line for offline analysis |

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

**Villages are complete.** Every Town Center base gets one Temple and one military building
(`godVillageMonitor`). The engine already builds temples slowly; we just make sure a new
village is never left without one.

### Defence

**One signal.** `gGodDefendHome` is read straight from `gDefensivelyOverrun`, the engine's
serious-trouble flag. There is no per-base threat calculation and no stance machine: the
engine already computes enemy power per defend base in `military_defend.xs`
(`gEnemyPowerInBases`) and moves its primary defend plan to the attacked base. When the flag
is set, the attack gate closes and the army stays with the towers.

**Turrets are upgraded immediately.** `godTowerUpgradeMonitor` researches the next
obtainable tower upgrade as soon as we own a tower, ignoring the stock time gates (4 minutes
in Classical, 5 in Heroic, 6 in Mythic). It follows the engine's own progression and culture
variants, publishes the plan through `gTowerOffensiveResearchPlanID`, and reuses the stock
`resetOffensiveTowerResearchPlan` handler so the stock monitor defers instead of stacking a
second plan.

**Towers are raised when needed.** While `gGodDefendHome` is set, the strategy asks the
engine's `towerManager` for `cGodDefendTowersPerBase` towers per base instead of its own
2-3, and nudges the rule once so the extra towers start immediately.
`godFrontTowerMonitor` then builds one tower on the side the enemy is massing from — the
engine's ring placement often leaves that approach open. The front tower is a build plan,
not an army plan, so it does not compete for units.

**Help an ally.** `godAssistMonitor` sends a capped share (`cGodAssistMaxSharePercent`) of
the land army to the ally base that most needs it — preferring the ally closest to being
wiped out, then the base where the enemy's edge is biggest. Only ally bases within
`cGodAssistMaxDistance` are considered. Our own bases come first: a defend-home flag cancels
the assist immediately, and the plan releases once the ally base has been safe for
`cGodAssistQuietSeconds`. It is the one custom plan that may claim the land army.

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
`cGodCadenceMultiplier` (1.2) and re-applied on every age change and cadence change. Setting
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
forth. While pushing the cadence drops to `cGodPushInterval` and raids stop so the army
stays massed. The push decision lives in `godPushMonitor` because it reads both armies.

**Retreat when it is not working.** `godRetreatMonitor` judges each attack in the field on
its own: the enemy count around it, and whether an enemy Titan is close. It pulls that
attack back when the enemy on the spot clearly outnumbers it. Pulling back the main army
also sets the next attack one interval out, so the bot regroups rather than re-committing. A
failed raid is simply called off. It leaves the engine's own Titan plans alone: a Titan is
one unit, so the outnumbered check would otherwise recall it on every pass and it would
never land.

**Never feed a Titan.** A Titan is one unit, so the outnumbered check never sees it, and it
kills an army faster than any count notices. `godTitanNear` calls off any attack standing
within `cGodTitanFleeRadius` of one, and `godTitanAllowsAttack()` vetoes the attack gate —
and the raid monitor, which reads it directly — while an enemy Titan is alive and we cannot
answer it: no Titan of our own and less than `cGodTitanHuntArmyPop` military pop. The army
waits at home with the towers and our own gate instead of walking into it; once the army is
big enough, or our own Titan is out, attacks resume on their normal rhythm.

**Raid what the enemy left open.** In one monitor, `godRaidMonitor` prefers cavalry at the
gold mine the enemy is working: cavalry outruns the defence, so that raid is judged by how
close the enemy is rather than by a count. Otherwise a small foot party goes at the enemy
drop site with the fewest troops on it (falling back to a villager). A raid is judged only
on the troops sitting on its target (`cGodRaidAbortRadius`), and a site whose own guard is
above `cGodRaidMaxGuard` is not raided at all. Raids stop while pushing or defending home.

### Endgame

**A stalemate unlocks both win conditions.** Once both sides have sat in Mythic for
`cGodStalemateSeconds` with no age lead, neither side is closing the game: the armies trade
at the pop cap and the bank piles up. `godUpdateStalemate` latches the stalemate, and
`godManageWinConditions` sets `cStrategyFlagBuildTitan` and `cStrategyFlagBuildWonder`.
Defending home postpones both.

**The engine does the rest.** `secretsOfTheTitansMonitor` researches Secrets of the Titans,
`titanGateConstructionMonitor` places the Gate, and the engine's Wonder monitor builds the
Wonder. The bot does not maintain a bank reserve, a favour exemption or a hold/release state
machine of its own: those were endgame micro-management that never produced a Titan in
three recorded matches.

### Team games

A 1v1 is one enemy and one front. A team game can leave an ally about to be wiped out, and
the 1v1 posture has no answer for that. The bot therefore keeps one team behaviour, the
ally assist, and gates it on a normal team shape: `gGodTeamGame` is true with at least one
ally and at most `cGodTeamMaxEnemies` enemies. A 12-player brawl is not treated as a 2v2, so
the thresholds tuned for a small team are not applied where they do not fit. Enemy and ally
counts are refreshed by `godPlayersMonitor` as players are eliminated.

## Telemetry

`godTelemetryMonitor` emits one line every 30s:

```
[GBOT] t=… age=… vills=… pop=cur/cap army=… food=… wood=… gold=… favor=… enemyAge=… enemyTitan=0|1 titans=… wonder=… state=hold|push underAttack=0|1 enemies=… allies=… defend=0|1 assist=<player-id>|-1
```

`state` is the push stance — `push` while the army is committed, `hold` otherwise.
`underAttack` is the engine's `gDefensivelyOverrun` flag, reported separately because the
push state does not change when a base is poked. `defend` is the defend-home decision,
`assist` names the ally being helped, and `enemies`/`allies` are the live player counts.

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
| `cGodRetreatEnemyRatioPercent` | Enemy-to-us ratio at the attack that triggers a retreat |
| `cGodRaidTargetRadius` | How close troops have to be to mark a raid target as defended |
| `cGodRaidAbortRadius` | How close troops have to be to the raid itself to call it off |
| `cGodRaidMaxGuard` | Guard above which a drop site is not worth raiding at all |
| `cGodCavRaidMinCavalry` | Cavalry needed before the gold raid will go |
| `cGodCavRaidMineRadius` | How close a miner has to be to count as working a mine |
| `cGodCavRaidRetreatRadius` | How close the enemy has to get to call the cavalry raid home |
| `cGodTitanFleeRadius` | How close an enemy Titan has to be to call an attack off |
| `cGodTitanHuntArmyPop` | Military pop needed to take an enemy Titan on |
| `cGodStalemateSeconds` | How long we must have sat in Mythic before the win conditions unlock |
| `cGodThreatMinPower` | Enemy power on a base worth a front tower |
| `cGodThreatExtraRadius` | Margin beyond a base's own radius for counting troops on it |
| `cGodDefendTowersPerBase` | Towers per TC base while defending home |
| `cGodFrontTowerDistance` | How far out from the base centre the front tower goes |
| `cGodAssistRatioPercent` | Enemy-to-ally power on an ally base that needs help |
| `cGodAssistMinEnemyPower` | Minimum enemy power for an ally base to need help |
| `cGodAssistMaxSharePercent` | Most of our land army sent to help an ally |
| `cGodAssistMinUnits` | Fewest units worth sending to an ally |
| `cGodAssistMaxDistance` | Furthest ally base we will walk to help |
| `cGodAssistQuietSeconds` | How long an ally base must be safe before we come home |
| `cGodAssistPriority` | Priority of the assist plan |
| `cGodTeamMaxEnemies` | Largest enemy count that still counts as a normal team game |

## Caveats

- **`gDefensivelyOverrun` is the only defence signal.** The engine updates
  `gEnemyPowerInBases` and the flag on its own cadence (`defendManager`, 5s), so the bot
  reads those rather than running a second per-base calculation. If a match needs a finer
  distinction than "overrun or not", add it here, not as another plan.
- **Assist is the one custom army plan.** It is capped, it releases on its own, and it is
  cancelled the moment our own base is overrun. Any new plan must replace it or the
  complexity budget in [`AGENTS.md`](../AGENTS.md) must be raised deliberately.
- **The minor-god picks are a first pass.** They follow each god's documented focus, not
  measured results; revisit once telemetry shows which games are lost and why.
- **The tuning numbers are starting points.** Retreat, raid and push thresholds are the
  first things to adjust after a game.
- **The endgame is delegated.** The engine's `secretsOfTheTitansMonitor` has its own
  surplus and favour checks. If a stalemate still produces no Titan, the failure is inside
  the engine's monitor: record the bank and the guard in `god-bot-record.md` before adding
  a manual purchase back.
- **The front tower is a heuristic.** The engine's tower ring does not face the attacker, so
  the bot builds one tower on the average direction of the enemy troops at the worst-hit
  base. It is judged from its own log lines.
