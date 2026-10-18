# AI Architecture — Authoring Bot Behavior

This document explains *how a bot is described* in the base game AI and how to reuse
that model in `custom_bot.xs`. It is the companion to [`AGENTS.md`](../AGENTS.md): that
file tells you **where** things live, this one tells you **how behavior is expressed**.

The goal is to let you describe a bot in plain language and translate it to XS without
needing to learn the full syntax.

---

## The core idea: bots are declarative

An XS bot does not issue frame-by-frame move or attack commands. It **declares policy**
and the engine's plan system executes it:

- "Keep N villagers alive."
- "Maintain this army composition."
- "Attack player X every M seconds with a wave of size S along this route."
- "Enable these automation behaviors; disable those."

Your job is to set the knobs. The engine handles production, gathering, pathing and
combat micro.

---

## Startup flow

`custom_bot.xs` includes the base game's `core/main.xs`, which drives everything and
calls two hooks you own:

```c
void main() {
   initCivUnitTypes();
   initArrays();
   preInit();              // ← your hook, before engine setup
   if (gInactiveAI == true) { ...; return; }
   doStartupFlow();
   initXSHandlers();
   ...
   prepareForInit();       // → init() → postInit() (your second hook)
}
```

| Hook | Runs | Use it for |
|---|---|---|
| `preInit()` | Before engine base-building and KB analysis | Override globals, install a custom strategy |
| `postInit()` | After engine startup completes | Tweak live plans, build orders, army plans |

---

## The strategy system

Behavior is organized into **strategies**. Each strategy targets one age and is scored
and swapped by `StrategyManager`. From `core/strategy/strategy_internal.xs`:

```c
class Strategy {
   StrategyData mData;
   int    mID;
   string mName;
   int    mAge;                                  // which age it applies to (cAge1..cAge5)
   bool(ref StrategyData) mInitFunc;             // set up policy; return false to abort
   bool(ref StrategyData) mUpdateFunc;           // runs every second; return false to end it
   float() mGetCurrentScore;                     // higher wins over the default strategy
   void(ref StrategyData) mDestroyFunc;          // cleanup
}
```

The simplest real example — the Attacker personality's Classical behavior
(`core/shared/classical/classical_rusher_strategy.xs`):

```c
void initClassicalRusherStrategy() {
   gClassicalRusherStrategy.mAge = cAge2;
   gClassicalRusherStrategy.mInitFunc = [](ref StrategyData data) -> bool {
      data.enableAllStrategyFlags();
      data.setFlag(cStrategyFlagAutoResearchEconomyUpgrades, false);
      float interval = selectByDifficulty(10, 7.5, 4.5, 3.5, 2.5, 2.5) * 60.0;
      gAttackManager.mBaseAttackInterval = interval;
      gAttackManager.mAttackInterval = interval;
      return true;
   };
   gClassicalRusherStrategy.mGetCurrentScore = []() -> float {
      return cStrategyDefaultStrategyValue + 10.0;   // outrank the default strat
   };
   gClassicalRusherStrategy.mUpdateFunc = [](ref StrategyData data) -> bool {
      return kbPlayerGetAge(cMyID) == cAge2;         // alive only during Classical
   };
}
```

### StrategyData — the policy surface

```c
class StrategyData {
   void setFlag(int flag, bool enable = true);                       // toggle automation
   int  addUnitToMaintain(int puid, int count, int pri, int cat);    // "keep N of this unit"
   void adjustUnitToMaintainAmount(int puid, int count, int pri);    // change the N
   void setTrainDelay(int puid, float delay);                        // seconds between queueing more
   void removeUnitToMaintain(int puid);
}
```

`setFlag` toggles the ~50 named policies the engine already knows how to fulfill. The
ones you'll reach for most:

| Flag | Effect |
|---|---|
| `cStrategyFlagAutomaticEco` | Assign villagers to resources automatically |
| `cStrategyFlagAutomaticVillagerTraining` | Keep training villagers |
| `cStrategyFlagBuildHouses` | Auto-build houses for population |
| `cStrategyFlagAutomaticTCRepair` | Repair the town center |
| `cStrategyFlagCanAttack` | Allow attacking |
| `cStrategyFlagAutomaticGodPowerUsage` | Use god powers |
| `cStrategyFlagAutoResearchEconomyUpgrades` | Research eco techs |
| `cStrategyFlagAutoResearchMilitaryUpgrades` | Research military techs |

`enableAllStrategyFlags()` turns everything on; disable selectively. The full list is in
`displayStrategyInformation()` in `core/strategy/strategy_internal.xs`.

---

## A full worked example

`campaign/fott/fott02_p2.xs` (base game) is the best single reference: attack
waves + naval + economy + timed escalation.

`preInit` overrides globals and installs the custom strategy:

```c
void preInit() {
   gOverrideMaxVillagerPop = gMaxVillagerCount;
   gMainGatherBase = createOverrideGatherBase(vector(237, 0, 121), 90);
   setOverrideStrategy(fott02StrategySetup);   // replaces the built-in strategy
   gOverrideFarmCount = 10;
}
```

The strategy declares economy and army policy:

```c
data.setFlag(cStrategyFlagAutomaticEco, true);
data.setFlag(cStrategyFlagAutomaticVillagerTraining, true);
data.setFlag(cStrategyFlagBuildHouses, true);
data.addUnitToMaintain(cUnitTypeSpearman, 3);   // keep 3 Spearmen
data.addUnitToMaintain(cUnitTypeKebenit, 1);
data.setTrainDelay(cUnitTypeSpearman, 3);       // queue at most every 3s
```

Attack waves are their own object (`gAttackWave`) with timing, size and routes:

```c
gAttackWave.setPlayerToAttack(1);
gAttackWave.setAttackStartTime(360);   // first attack at 6 min
gAttackWave.setAttackInterval(360);    // every 6 min after
gAttackWave.setAttackSize(5);          // 5 units in the first wave
gAttackWave.setMaxAttackSize(12);
gAttackWave.addAttackUnitType(cUnitTypeSpearman);

int routeID = kbCreateAttackRouteWithPath("Route To P1", startPoint, enemyTC);
// ... add waypoints ...
gAttackWave.setAttackRouteID(routeID);
gAttackWave.setGatherPoint(startPoint);   // units mass here before striking
gAttackWave.setTargetPoint(enemyTC);
```

The `mUpdateFunc` runs every second and is where *dynamic* behavior lives:

```c
strategy.mUpdateFunc = [](ref StrategyData data) -> bool {
   static bool done = false;
   if (!done && xsGetTime() >= gSecondLandUnitDelay) {
      done = true;
      data.addUnitToMaintain(cUnitTypeAxeman, 4);   // start training Axemen later
      gAttackWave.addAttackUnitType(cUnitTypeAxeman);
   }
   gAttackWave.update();
   return true;   // keep the strategy alive
};
```

---

## Rules — one-off and periodic actions

`rule` blocks are the engine's event system. They run on an interval and typically
self-disable once done. Use them for research, single builds, or conditional triggers:

```c
rule researchMediumSpearmen
inactive
minInterval 90
{
   if (kbTechGetStatus(cTechMediumSpearmen) == cTechStatusActive) {
      xsDisableRule("researchMediumSpearmen");
      return;
   } else if (kbTechGetStatus(cTechMediumSpearmen) == cTechStatusObtainable) {
      researchSimpleTech(cTechMediumSpearmen, cUnitTypeBarracks, -1, 60);
   }
}
```

---

## Defend plans

Defend plans keep a body of units parked at a base or point. `fott04_p3.xs` (the minimal
gather-only bot) creates one alongside its gather flags:

```c
int landDefendPlan = createDefendPlan("Primary Land Defend", kbBaseGetMainID(cMyID),
   30.0, vector(38.0, 0, 200.0));
aiPlanAddUnitType(landDefendPlan, cUnitTypeLogicalTypeLandMilitary, 0, 0, 200);
```

`createDefendPlan` (base ID) and `createDefendPlanForPoint` (explicit point) are both in
`core/scenario/scenario_attack_wave_strategy.xs`.

---

## Build orders are a separate system

Opening build orders (the first ~7 villagers) live in `core/<culture>/<culture>_archaic.xs`
and use a sequential DSL:

```c
boVillager(cUnitTypeVillagerGreek, cResourceFood);
boBuild(cUnitTypeGranary, cUnitTypeVillagerGreek, 4, boBuildFoodDropsite, "internalBOBuildDropsiteComplete");
boExplore(cUnitTypeKataskopos, ...);
```

You normally inherit these via `core/main.xs` and only override the **strategy** layer.
Override the build order only when the opening itself must change.

---

## Translation cheat-sheet

| Desired behavior | Where to express it |
|---|---|
| Cap villagers / farms | `gOverrideMaxVillagerPop`, `gOverrideFarmCount` in `preInit` |
| Enable/disable gathering or building | `data.setFlag(...)` in the strategy `mInitFunc` |
| Army composition | `data.addUnitToMaintain(unit, count)` + `setTrainDelay` |
| Attack timing, size, target, route | `gAttackWave.*` setters + `gAttackWave.update()` |
| Change plans over time | mutate the same knobs in `mUpdateFunc`, gated by `xsGetTime()` |
| Research a tech / one-off build | a `rule` block with `minInterval` |
| Hold units at home | `createDefendPlan` / `createDefendPlanForPoint` |

### Worked translation

> "Boom to Heroic with ~30 villagers, then spam Hoplites and attack the nearest enemy
> every 3 minutes, keeping 8 units home to defend."

1. `preInit`: `gOverrideMaxVillagerPop = 30;`
2. Strategy `mInitFunc`: enable `cStrategyFlagAutomaticEco`, `AutomaticVillagerTraining`,
   `BuildHouses`; `addUnitToMaintain(cUnitTypeHoplite, 20)`.
3. Attack wave: `setAttackInterval(180)`, `addAttackUnitType(cUnitTypeHoplite)`,
   `setPlayerToAttack(<nearest enemy>)`.
4. Defend plan: `createDefendPlan(...)` with 8 units assigned.
5. `mUpdateFunc`: call `gAttackWave.update()`, return `true`.

---

## Reference

- `core/strategy/strategy_internal.xs` — `Strategy`, `StrategyData`, `StrategyManager`.
- `core/strategy/strategy.xs` — strategy IDs and age constants.
- `core/scenario/scenario_attack_wave_strategy.xs` — `AttackWave`, defend-plan helpers.
- `core/shared/*/*_strategy.xs` — stock strategies per age and personality.
- `core/globals_override.xs` — all override variables.
- Base game campaign bots — the best end-to-end examples:
  - `campaign/fott/fott02_p2.xs` — attack waves + naval + economy + escalation.
  - `campaign/fott/fott04_p3.xs` — minimal gather-only bot (~90 lines).
