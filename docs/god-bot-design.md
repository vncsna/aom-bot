# God Bot Design

How the God Bot in `game/ai/god_bot.xs` is put together and why. Background on how bot
behaviour is expressed lives in [`ai-architecture.md`](ai-architecture.md).

## Goal

**Always win.** The bot plays every 1v1 against the stock personalities to win, and it is
expected to win by using powers a human player does not have. A loss is a bug to be
diagnosed from the telemetry, not an acceptable outcome of a fair game.

## Bot powers

The player sees a fogged map and acts on scouted information. The bot is not held to that.
It reads the game state directly through the knowledge base, so everything below is known
the moment it matters, with no scout and no guess:

- **The enemy's army, anywhere.** `godEnemyMilitaryNear()` counts the enemy's land military
  around any point on the map, and `kbUnitCount()` gives the enemy's army size, age, town
  centres and villager count.
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

The bot is a Conqueror at heart: slow, territorial, economy-heavy. Three levers get it to
the goal:

1. **An economy that outlasts.** More bases, more housing, upgrades online early.
2. **A defence that holds the early game.** Turrets that are actually worth building, and
   no greedy Wonder/Titan Gate while the base is under pressure.
3. **Attacks that only commit when the bot knows they are worth it.** A slow rhythm, a
   willingness to pull back, and raids aimed at whatever the enemy left open.

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
- The strategy enables every engine flag, then applies our policy (naval off, slow cadence).
  A strategy update runs once a second for the policy that has to react to the live game
  (tiny-map housing, Wonder/Titan Gate gating, push state).
- Monitors handle everything that is naturally periodic. They are enabled in `postInit()`.

| Piece | Where | Job |
|---|---|---|
| Strategy | `godBotStrategy()` | Base policy: flags, naval, attack cadence, push state |
| `godNavalCleanupMonitor` | 30s | Scrap warships on non-naval maps |
| `godVillageMonitor` | 20s | One Temple + one military building per village |
| `godTowerUpgradeMonitor` | 10s | Research tower upgrades as early as possible |
| `godRetreatMonitor` | 10s | Pull an attack back when it is bleeding out |
| `godRaidMonitor` | 90s | Hit the enemy economy with a small group |
| `godCavRaidMonitor` | 60s | Cavalry raid on the gold mine the enemy is working |
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

**Tiny maps build houses before the Armory.** On `tiny`, once the Temple is up the Armory is
held until there is a comfortable pop buffer, and houses are pushed in the meantime. Housing
is what turns a small map into a workable army, so it comes first.

### Defence

**Turrets are upgraded immediately.** `godTowerUpgradeMonitor` researches the next
obtainable tower upgrade as soon as we own a tower, ignoring the stock time gates (4 minutes
in Classical, 5 in Heroic, 6 in Mythic). It follows the engine's own progression and culture
variants, publishes the plan through `gTowerOffensiveResearchPlanID`, and reuses the stock
`resetOffensiveTowerResearchPlan` handler so the stock monitor defers instead of stacking a
second plan.

**No Wonder or Titan Gate under pressure.** While `gDefensivelyOverrun` is set, the Wonder
flag is cleared and any Wonder build plan cancelled; an uncommitted Titan Gate is postponed.
Resources fall back to the normal economy and military building rules, which is what we want
mid-defence. A gate already under construction is left alone so the investment is not
wasted, and the bot re-arms it once the attack is over.

### Navy

Naval military only exists on a map that is really naval: an island map, or one where we
start on a transport. Everywhere else the naval flags are cleared,
`gOverrideNavalMaxMilitaryPop` is pinned to 0, and `godNavalCleanupMonitor` deletes any
warship that slips through, naming the unit it deletes so a leak can be traced back to its
source. The policy is re-applied at every age change, not only at init, because the engine
re-enables its default flags as the game goes on. Fishing and Docks are untouched — this is
about warships only.

### Offence

**A slow rhythm.** Conqueror's attack interval (by difficulty) is multiplied by
`cGodCadenceMultiplier` and re-applied on every age change. The bot should be threatening,
not frantic.

**A decisive push once the bot knows it is ahead.** `godShouldPush()` fires when we are in
Heroic or later, have a real army (`cGodPushArmyPop`), and either we are an age ahead or we
outgun the enemy — read directly, not estimated — by `cGodPushAdvantagePercent`. While
pushing the cadence drops to `cGodPushInterval` and the foot raid stops so the army stays
massed; the cavalry raid is allowed to run, because it is the one that wants the enemy army
busy elsewhere. A brief defend state only blocks *starting* a push; a push already under way
continues unless the army itself collapses below the bar.

**Retreat when it is not working.** `godRetreatMonitor` judges each attack in the field on
its own: its army pop over the loss window, and the enemy count around it. It pulls that
attack back when either a large share of it dies within the window, or the enemy on the spot
clearly outnumbers it. Pulling back the main army also pushes the next attack out, so it
regroups rather than re-committing; a failed raid is simply called off.

**Never feed a Titan.** A Titan is one unit, so the outnumbered check never sees it, and it
kills an army faster than the loss window notices. `godTitanNear` calls off any attack
standing within `cGodTitanFleeRadius` of one, and `godApplyTitanPolicy` holds attacks and
raids entirely while an enemy Titan is alive and we cannot answer it — no Titan of our own
and less than `cGodTitanHuntArmyPop` military pop. The army waits at home with the towers and
our own gate instead of walking into it; once the army is big enough, or our own Titan is
out, attacks resume on their normal rhythm.

**Raid what the enemy left open.** When we cannot commit to a real attack and have spare
army, `godRaidMonitor` sends a small group at the enemy drop site with the fewest troops on
it (falling back to a villager) to keep the pressure on without risking the main force. A
raid is judged only on the troops sitting on its target (`cGodRaidAbortRadius`), so a base
that happens to be garrisoned elsewhere does not call it off before it lands. A site whose
own guard is above `cGodRaidMaxGuard` is not raided at all: a party of eight cannot fight a
garrison, and walking one in only loses the party.

**Raid the gold with cavalry.** `godCavRaidMonitor` sends cavalry at the enemy gold mine
with the most miners on it, and may run while the main army is pushing — that is exactly
when the enemy's army is away from its mines. Cavalry outruns the defence, so this raid is
not judged on an enemy count at all: it keeps going while the enemy is further than
`cGodCavRaidRetreatRadius` away, and comes home once they close in.

## Telemetry

`godTelemetryMonitor` emits one line every 30s:

```
[GBOT] t=… age=… vills=… pop=cur/cap army=… food=… wood=… gold=… enemyAge=… enemyTitan=0|1 state=hold|push|defend
```

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
| `cGodHousePopHeadroomBase` | Free pop wanted before the Armory is allowed on tiny maps |
| `cGodRetreatLossPercent` | Share of the army lost that triggers a retreat |
| `cGodRetreatLossWindow` | How long that loss has to happen within |
| `cGodRetreatEnemyRatioPercent` | Enemy-to-us ratio at the attack that triggers a retreat |
| `cGodRaidTargetRadius` | How close troops have to be to mark a raid target as defended |
| `cGodRaidAbortRadius` | How close troops have to be to the raid itself to call it off |
| `cGodRaidMaxGuard` | Guard above which a drop site is not worth raiding at all |
| `cGodCavRaidMinCavalry` | Cavalry needed before the gold raid will go |
| `cGodCavRaidMineRadius` | How close a miner has to be to count as working a mine |
| `cGodCavRaidRetreatRadius` | How close the enemy has to get to call the cavalry raid home |

## Caveats

- **"Under attack" means `gDefensivelyOverrun`.** That is the engine's serious-trouble
  signal, so the Wonder/Titan Gate gating only kicks in under real pressure.
- **The minor-god picks are a first pass.** They follow each god's documented focus, not
  measured results; revisit once telemetry shows which games are lost and why.
- **The tuning numbers are starting points.** Retreat, raid and push thresholds are the
  first things to adjust after a game.
