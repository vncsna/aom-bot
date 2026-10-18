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
implemented directly instead.

## Architecture

- `preInit()` installs the override strategy. The stock strategies are never added.
- The strategy enables every engine flag, then applies our policy (naval off, slow
  cadence). A strategy update runs once a second for the policy that has to react to the
  live game (tiny-map housing, Wonder/Titan Gate gating).
- Four monitors handle everything that is naturally periodic. They are enabled in
  `postInit()`.

| Piece | Where | Job |
|---|---|---|
| Strategy | `customBotStrategy()` | Base policy: flags, naval, attack cadence |
| `customNavalCleanupMonitor` | 30s | Scrap warships on non-naval maps |
| `customVillageMonitor` | 20s | One Temple + one military building per village |
| `customTowerUpgradeMonitor` | 10s | Research tower upgrades as early as possible |
| `customRetreatMonitor` | 10s | Pull an attack back when it is bleeding out |
| `customRaidMonitor` | 90s | Hit the enemy economy with a small group |

## Behaviour

### Economy and expansion

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

**Retreat when it is not working.** `customRetreatMonitor` samples the attacking army's pop
and the enemy count around the attack. It pulls the army back when either a large share of
it dies quickly, or the enemy on the spot clearly outnumbers us. Pulling back also pushes
the next attack out, so the army regroups rather than re-committing.

**Raid the economy otherwise.** When we cannot commit to a real attack and have spare army,
`customRaidMonitor` sends a small group at an enemy drop site (falling back to a villager)
to keep the pressure on without risking the main force.

## Tuning

| Constant | Meaning |
|---|---|
| `cCustomCadenceMultiplier` | Extra slowdown on top of Conqueror's attack interval |
| `cCustomHousePopHeadroomBase` | Free pop wanted before the Armory is allowed on tiny maps |
| `cCustomRetreatLossPercent` | Share of the army lost that triggers a retreat |
| `cCustomRetreatLossWindow` | How long that loss has to happen within |
| `cCustomRetreatEnemyRatioPercent` | Enemy-to-us ratio at the attack that triggers a retreat |

## Caveats

- **Not yet run in-game.** XS cannot be linted here. The file follows the same patterns as
  the base game scripts and the shipped campaign bots, but it needs a live match to confirm.
- **The retreat and raid numbers are starting points.** They are the first things to tune
  after a game; the raid in particular only targets the first enemy drop site it finds and
  does not yet prefer gold mines specifically.
- **"Under attack" means `gDefensivelyOverrun`.** That is the engine's serious-trouble
  signal, so the Wonder/Titan Gate gating only kicks in under real pressure.
