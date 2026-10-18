# Custom Bot Design

How the custom bot in `game/ai/custom_bot.xs` is put together and why. Background on
how bot behaviour is expressed lives in [`ai-architecture.md`](ai-architecture.md).

## Goal

Win a 1v1 against the stock personalities on the same maps, at the same difficulty.

## Approach

The bot is a Conqueror at heart: slow, territorial, economy-heavy. Three levers get us
to the goal:

1. **An economy that outlasts.** More bases, more housing, upgrades online early.
2. **A defence that holds the early game.** Turrets that are actually worth building, and
   no greedy Wonder/Titan Gate while the base is under pressure.
3. **Attacks that only commit when they are worth it.** A slow rhythm, a willingness to
   pull back, and cheap raids when a real push is not on the table.

## Identity

`CustomBot.personality` is purely cosmetic — it points the skirmish lobby name, tooltip
and portrait at the Conqueror strings. Behaviour is not driven by the personality at all:
per the official `How-to create your own skirmish AI.pdf`, the name in
`personalities_mods.xml` generates the script constant (`CustomBot` → `cPersonalityCustomBot`),
so we can never satisfy `cPersonalityCurrent == cPersonalityConqueror`. Because the bot
replaces the strategy system with `setOverrideStrategy`, the Conqueror tuning is
implemented directly instead. The generated index also makes the stock name lookup warn at
startup (`Unknown cPersonalityCurrent.`); that is harmless unless `aiDebugScript` is on,
where the warning becomes a debugger breakpoint that freezes the bot — see the AI Debugger
Config section in [`AGENTS.md`](../AGENTS.md).

## Architecture

- `preInit()` sets the economy target and the minor-god picks, then installs the override
  strategy. The stock strategies are never added.
- The strategy enables every engine flag, then applies our policy (naval off, slow
  cadence). A strategy update runs once a second for the policy that has to react to the
  live game (tiny-map housing, Wonder/Titan Gate gating, push state).
- Monitors handle everything that is naturally periodic. They are enabled in `postInit()`.

| Piece | Where | Job |
|---|---|---|
| Strategy | `customBotStrategy()` | Base policy: flags, naval, attack cadence, push state |
| `customNavalCleanupMonitor` | 30s | Scrap warships on non-naval maps |
| `customVillageMonitor` | 20s | One Temple + one military building per village |
| `customTowerUpgradeMonitor` | 10s | Research tower upgrades as early as possible |
| `customRetreatMonitor` | 10s | Pull an attack back when it is bleeding out |
| `customRaidMonitor` | 90s | Hit the enemy economy with a small group |
| `customTelemetryMonitor` | 30s | Emit a `[CBOT]` metrics line for offline analysis |

## Behaviour

### Economy and expansion

**A real boom.** `preInit()` sets `gOverrideMaxVillagerPop` so the engine's auto-eco
maintains a large villager count. Conqueror is eco-heavy; the villager mass is what funds
a slow push.

**Minor gods are chosen, not rolled.** The engine picks the Classical/Heroic/Mythic minor
god at random. We set `gOverrideClassicalMinorGod` / `gOverrideHeroicMinorGod` /
`gOverrideMythicMinorGod` per major god, favouring economy, defence and late-game
upgrades. The picks and the matchups behind them are in
[`custom-bot-minor-gods.md`](custom-bot-minor-gods.md).

**Villages are complete.** Every Town Center base gets one Temple and one military
building (`customVillageMonitor`). The engine already builds temples slowly; we just make
sure a new village is never left without one.

**Tiny maps build houses before the Armory.** On `tiny`, once the Temple is up the Armory
is held until there is a comfortable pop buffer, and houses are pushed in the meantime.
Housing is what turns a small map into a workable army, so it comes first.

### Defence

**Turrets are upgraded immediately.** `customTowerUpgradeMonitor` researches the next
obtainable tower upgrade as soon as we own a tower, ignoring the stock time gates (4
minutes in Classical, 5 in Heroic, 6 in Mythic). It follows the engine's own progression
and culture variants, publishes the plan through `gTowerOffensiveResearchPlanID`, and
reuses the stock `resetOffensiveTowerResearchPlan` handler so the stock monitor defers
instead of stacking a second plan.

**No Wonder or Titan Gate under pressure.** While `gDefensivelyOverrun` is set, the Wonder
flag is cleared and any Wonder build plan cancelled; an uncommitted Titan Gate is
postponed. Resources fall back to the normal economy and military building rules, which is
what we want mid-defence. A gate already under construction is left alone so the
investment is not wasted, and the bot re-arms it once the attack is over.

### Navy

Naval military only exists on a map that is really naval: an island map, or one where we
start on a transport. Everywhere else the naval flags are cleared, `gOverrideNavalMaxMilitaryPop`
is pinned to 0, and `customNavalCleanupMonitor` deletes any warship that slips through.
Fishing and Docks are untouched — this is about warships only.

### Offence

**A slow rhythm.** Conqueror's attack interval (by difficulty) is multiplied by
`cCustomCadenceMultiplier` and re-applied on every age change. The bot should be
threatening, not frantic.

**A decisive push when we are clearly ahead.** `customShouldPush()` fires when we are in
Heroic or later, have a real army (`cCustomPushArmyPop`), and either the enemy is down to
one base or we are an age ahead. While pushing the cadence drops to `cCustomPushInterval`
and raids stop so the army stays massed. It is deliberately conservative — we only stop
being patient once the game is effectively won.

**Retreat when it is not working.** `customRetreatMonitor` judges each attack in the field
on its own: its army pop over the loss window, and the enemy count around it. It pulls that
attack back when either a large share of it dies within the window, or the enemy on the
spot clearly outnumbers it. Pulling back the main army also pushes the next attack out, so
it regroups rather than re-committing; a failed raid is simply called off.

**Raid the economy otherwise.** When we cannot commit to a real attack and have spare army,
`customRaidMonitor` sends a small group at an enemy drop site (falling back to a villager)
to keep the pressure on without risking the main force.

## Telemetry

`customTelemetryMonitor` emits one line every 30s:

```
[CBOT] t=… age=… vills=… pop=cur/cap army=… food=… wood=… gold=… enemyAge=… state=hold|push|defend
```

It lands in the per-player AI log, `temp/Logs/MythRetoldAIOutputPlayer<N>.txt` (UTF-16).
`scripts/parse_ai_log.py` turns it into a per-run summary. This is the feedback loop that
turns the tuning constants from guesses into measurements; the log locations and the
run-metadata options are documented in [`../AGENTS.md`](../AGENTS.md).

## Tuning

| Constant | Meaning |
|---|---|
| `cCustomCadenceMultiplier` | Extra slowdown on top of Conqueror's attack interval |
| `cCustomMaxVillagerPop` | Villager count the economy targets |
| `cCustomPushArmyPop` | Military pop required before we commit to a decisive push |
| `cCustomPushInterval` | Seconds between attacks while pushing |
| `cCustomHousePopHeadroomBase` | Free pop wanted before the Armory is allowed on tiny maps |
| `cCustomRetreatLossPercent` | Share of the army lost that triggers a retreat |
| `cCustomRetreatLossWindow` | How long that loss has to happen within |
| `cCustomRetreatEnemyRatioPercent` | Enemy-to-us ratio at the attack that triggers a retreat |

## Caveats

- **Not yet run in-game.** XS cannot be linted here. The file follows the same patterns as
  the base game scripts and the shipped campaign bots, but it needs a live match to confirm.
- **The minor-god picks are a first pass.** They follow each god's documented focus, not
  measured results; revisit once telemetry shows which games are lost and why.
- **The tuning numbers are starting points.** Retreat, raid and push thresholds are the
  first things to adjust after a game; the raid in particular only targets the first enemy
  drop site it finds and does not yet prefer gold mines specifically.
- **"Under attack" means `gDefensivelyOverrun`.** That is the engine's serious-trouble
  signal, so the Wonder/Titan Gate gating only kicks in under real pressure.
