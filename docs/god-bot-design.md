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

A 1v1 has one enemy and one front, so those three levers are enough. A team game can put
two or more enemies on our bases at once, or leave an ally about to be wiped out, and the
1v1 posture has no answer for either. The bot therefore reads the shape of the game each
second and picks a **stance**; in a 1v1 it never leaves the original stance, so the tested
1v1 behaviour is unchanged. See [Team games](#team-games).

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
  (Wonder/Titan Gate gating, push state, the threat reading and the stance).
- Monitors handle everything that is naturally periodic. They are enabled in `postInit()`.

| Piece | Where | Job |
|---|---|---|
| Strategy | `godBotStrategy()` | Base policy: flags, naval, attack cadence and gate, push state, stalemate Titan, threat reading and stance |
| `godNavalCleanupMonitor` | 30s | Scrap warships on non-naval maps |
| `godPlayersMonitor` | 30s | Recount the enemies and allies still in the game |
| `godVillageMonitor` | 20s | One Temple + one military building per village |
| `godTowerUpgradeMonitor` | 10s | Research tower upgrades as early as possible |
| `godRetreatMonitor` | 10s | Pull an attack back when it is bleeding out |
| `godFallbackMonitor` | 5s | Move the army to our strongest defended base when it is losing |
| `godAssistMonitor` | 10s | Send a capped share of the army to an ally about to lose a base |
| `godFrontTowerMonitor` | 30s | Build a tower toward the enemy while fortifying |
| `godChokeMonitor` | 15s | Hold the choke between us and the attacking enemy while fortifying |
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

### Defence

**Turrets are upgraded immediately.** `godTowerUpgradeMonitor` researches the next
obtainable tower upgrade as soon as we own a tower, ignoring the stock time gates (4 minutes
in Classical, 5 in Heroic, 6 in Mythic). It follows the engine's own progression and culture
variants, publishes the plan through `gTowerOffensiveResearchPlanID`, and reuses the stock
`resetOffensiveTowerResearchPlan` handler so the stock monitor defers instead of stacking a
second plan.

**A Titan breaks a stalemate.** Once both sides have sat in Mythic for
`cGodStalemateSeconds` with no age lead, neither side is closing the game: the armies trade
at the pop cap and the bank piles up. A stalemate unlocks both win conditions. The Titan comes
first in practice — research `cTechSecretsOfTheTitans` for the first Titan Gate, and the
Wonder is allowed too, because a Wonder is what unlocks more Titans (`titanGateRebuyMonitor`,
and re-research once the Wonder Age rules are on). The bot does not wait for the Titan before
the Wonder: a Titan the game will not offer, or will not pay for, must not take the Wonder
down with it — that is what left the 19 Oct match grinding for 44 stalemated minutes with
33k wood banked and no win condition on the map.

**The Titan is bought from the bank.** The engine's own `secretsOfTheTitansMonitor` waits
for a surplus its needs bookkeeping reports, which in practice is long after the bank is
already full — the 19 Oct match held its Titan back to 31:00 with 30k banked. The bot reads
the bank directly instead: `godResearchTitanTech` starts the research as soon as the bank
covers the tech plus `cGodTitanReservePercent` on top, so the army keeps training. Favour is
exempt from that reserve: it is not banked like food, wood and gold but spent as it arrives
on myth units, so a reserve on top of it is a surplus that never comes. A tech uses no
builders and no army, so the Titan costs the army nothing while it is bought. When a
stalemate is latched and the tech is *not* bought, the guard that held it is named once a
minute (`Titan held: …`, with the bank beside it) — otherwise only the successful purchase
logs, and a stalled stalemate looks exactly like a satisfied one.

**No Wonder or Titan Gate under pressure.** While `gDefensivelyOverrun` is set, any Wonder
build plan is cancelled and an uncommitted Titan Gate is postponed. The stalemate flag stays
set, so the project resumes once the attack is over; a gate already under construction is
left alone so the investment is not wasted. Neither flag is set while fortifying, so a long
investment is never started with the enemy on our bases.

### Navy

Naval military only exists on a map that is really naval: an island map, or one where we
start on a transport. Everywhere else the naval flags are cleared,
`gOverrideNavalMaxMilitaryPop` is pinned to 0, and `godNavalCleanupMonitor` deletes any
warship that slips through, naming the unit it deletes so a leak can be traced back to its
source. The policy is re-applied at every age change, not only at init, because the engine
re-enables its default flags as the game goes on. Fishing and Docks are untouched — this is
about warships only.

### Offence

**A slow rhythm the bot holds itself.** Conqueror's attack interval (by difficulty) is
multiplied by `cGodCadenceMultiplier` and re-applied on every age change. Setting the interval
is not enough on its own: the engine's `attackManager` randomises it on every launch, and on
Hard and above it skips the time check altogether once the army is large or the resources are
in excess — and the personality the mod generates is not on the engine's "attack less
frequently" list. So the bot drives `cStrategyFlagCanAttack` itself and opens it only once its
own interval has elapsed. The engine still decides what to attack and how; the rhythm is ours.

**A decisive push once the bot knows it is ahead.** `godShouldPush()` fires when we are in
Heroic or later, have a real army (`cGodPushArmyPop`), and either we are an age ahead or we
outgun the enemy — read directly, not estimated — by `cGodPushAdvantagePercent`. The
comparison is on army power, not on a unit count, so a hero is not one slinger; and it is
asymmetric: committing takes the full margin, staying committed only takes
`cGodPushHoldPercent`, so a wobble around the threshold cannot flip the cadence back and
forth. While pushing the cadence drops to `cGodPushInterval` and the foot raid stops so the
army stays massed; the cavalry raid is allowed to run, because it is the one that wants the
enemy army busy elsewhere. A brief defend state only blocks *starting* a push; a push already
under way continues unless the army itself collapses below the bar.

**Retreat when it is not working.** `godRetreatMonitor` judges each attack in the field on
its own: its army pop over the loss window, and the enemy count around it. It pulls that
attack back when either a large share of it dies within the window, or the enemy on the spot
clearly outnumbers it. Pulling back the main army also pushes the next attack out by one full
interval of the rhythm the bot is on — the fast one while pushing, the slow one otherwise —
set explicitly, so the wait is deliberate rather than whatever the last cadence write left
behind. It regroups rather than re-committing, and a failed raid is simply called off. It
leaves the engine's own Titan plans alone: a Titan is one unit, so the outnumbered check
would otherwise recall it on every pass and it would never land.

**Never feed a Titan.** A Titan is one unit, so the outnumbered check never sees it, and it
kills an army faster than the loss window notices. `godTitanNear` calls off any attack
standing within `cGodTitanFleeRadius` of one, and `godTitanAllowsAttack()` vetoes the attack
gate — and the raids, which read it directly rather than the strategy flag — while an enemy
Titan is alive and we cannot answer it: no Titan of our own and less than
`cGodTitanHuntArmyPop` military pop. The army waits at home with the towers and our own gate
instead of walking into it; once the army is big enough, or our own Titan is out, attacks
resume on their normal rhythm.

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

### Team games

A 1v1 is one enemy and one front. A team game can put two or three enemies on our bases at
once, or leave an ally about to be wiped out, and the 1v1 posture has no answer for either:
its raids assume the enemy's army is away, and its defence only reacts to one global
under-attack flag. The bot reads the shape of the game every second and picks a **stance**.
The reading and the stance are only ever non-default in a team game, so a 1v1 runs the
original code paths unchanged.

**The game shape.** `godCountPlayers()` counts the live enemies and allies (the same loop
`core/chats.xs` uses to total team scores). `gGodTeamGame` is set when there is more than
one enemy or any ally. `godPlayersMonitor` refreshes it every 30s as players are eliminated.

**The threat, per base and per player.** `godUpdateThreat()` adds up the enemy land-military
power on each of our Town Center bases — and, separately, how many distinct enemy players
have a real force (`cGodThreatMinPower`) on any of them. "Three raids from three players"
then reads as three players on our bases, instead of one global flag. This is what the
fortify stance and the fallback rule both decide from.

**Stances.** `godPickStance()` returns one of three:

- **normal** — the 1v1 behaviour, unchanged. Also the state of a team game with no pressure.
- **fortify** — two or more enemy players are on our bases, or the enemy on our bases outguns
  the army at home (`cGodFortifyThreatPercent`). The stance is sticky: it holds for
  `cGodFortifyQuietSeconds` after the bases go quiet, so it cannot flicker as raiders step in
  and out of a base radius. While fortified: no raids, no push, no Wonder or Titan Gate, the
  army stays home, and the engine is told to keep `cGodFortifyTowersPerBase` towers per base
  instead of its own 2-3 (`data.mTowerAmountPerTCBase`, read by the engine's `towerManager`).
  This is the direct answer to "focus on towers": upgrades were already immediate, but the
  count was the engine's.
- **assist** — an ally base is being overrun and our own bases are quiet.

**Fall back to the strongest base.** `godFallbackMonitor` runs in every stance, not only team
games: a 1v1 army losing a fight in the open should fall back too. When the enemy on a base
outguns our army there (`cGodFallbackRatioPercent`), it recalls any attack still walking out
(`retreatArmies`) and parks the army on our most defensible base — scored by towers, Town
Center, Fortress and houses (`godBaseDefenceScore`). Fighting under those is worth giving up
ground for. The plan outranks the engine's primary defend plan so the units move across. It
releases after `cGodFallbackHoldSeconds`, or once the enemy has dropped back
(`cGodFallbackReleasePercent`), and while it is active the engine cannot attack or raid.

**Help an ally.** `godAssistMonitor` sends a capped share (`cGodAssistMaxSharePercent`) of the
land army to the ally base that most needs it — preferring the ally closest to being wiped
out, then the base where the enemy's edge is biggest. Only ally bases within
`cGodAssistMaxDistance` are considered, so the army is not sent across the map. Our own bases
come first: a fortify or a fallback at home cancels the assist immediately. Losing an ally
leaves us facing all the enemies alone, which is how the last team game ended.

**Hold the choke.** `godChokeMonitor` stations the army, while fortifying, on the narrowest
ground between us and the enemy pressing us, so the fight happens at the choke instead of
inside the economy. The engine exposes no "choke" concept, so `godFindChoke()` reads the area
graph the map is built from: it walks the land area path from our main base to the enemy's
and takes the area much smaller than the rest of the path (`cGodChokeMaxTilesPercent`), on our
half of the map. When the map has no clear narrow ground — or the path is impassable — it
falls back to a point on the straight line to the enemy. A fallback always wins the army back.

**Towers on the threatened side.** The engine's `towerManager` places towers on a random ring
around the Town Center, so the approach the enemy uses is often left open.
`godFrontTowerMonitor` finds the enemy's centroid at the worst-hit base and builds one tower
between the base and that direction (`godBuildTowerAt`).

## Telemetry

`godTelemetryMonitor` emits one line every 30s:

```
[GBOT] t=… age=… vills=… pop=cur/cap army=… food=… wood=… gold=… favor=… enemyAge=… enemyTitan=0|1 state=hold|push underAttack=0|1 enemies=… allies=… stance=normal|fortify|assist threat=… threatPlayers=… fallback=0|1 assist=<player-id>|-1
```

`state` is the push stance — `push` while the army is committed to a decisive push, `hold`
otherwise. Being under attack is a separate field because the push stance does not change
when a base is poked: the army stays in the field, and folding the two together would hide
it. `stance` is the team-game stance (`normal`/`fortify`/`assist`), `threat` and
`threatPlayers` are the enemy power on our bases and how many players it belongs to,
`fallback` is set while the army is falling back, and `assist` names the ally being helped.

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
| `cGodTitanFleeRadius` | How close an enemy Titan has to be to call an attack off |
| `cGodTitanHuntArmyPop` | Military pop needed to take an enemy Titan on |
| `cGodStalemateSeconds` | How long we must have sat in Mythic before going for a Titan |
| `cGodTitanReservePercent` | Extra share of the Titan tech's cost the bank must hold before it is bought (favour is exempt) |
| `cGodTitanBlockedLogSeconds` | How often to say why the Titan is not being bought once stalemated |
| `cGodPushArmyPop` | Military pop required before we commit to a decisive push |
| `cGodPushInterval` | Seconds between attacks while pushing |
| `cGodPushAdvantagePercent` | How much bigger our army must be than the enemy's to push |
| `cGodPushHoldPercent` | How much bigger it must stay to keep pushing |
| `cGodRetreatLossPercent` | Share of the army lost that triggers a retreat |
| `cGodRetreatLossWindow` | How long that loss has to happen within |
| `cGodRetreatEnemyRatioPercent` | Enemy-to-us ratio at the attack that triggers a retreat |
| `cGodRaidTargetRadius` | How close troops have to be to mark a raid target as defended |
| `cGodRaidAbortRadius` | How close troops have to be to the raid itself to call it off |
| `cGodRaidMaxGuard` | Guard above which a drop site is not worth raiding at all |
| `cGodCavRaidMinCavalry` | Cavalry needed before the gold raid will go |
| `cGodCavRaidMineRadius` | How close a miner has to be to count as working a mine |
| `cGodCavRaidRetreatRadius` | How close the enemy has to get to call the cavalry raid home |
| `cGodThreatMinPower` | Army power on a base that counts as an enemy pressing it |
| `cGodThreatExtraRadius` | Margin beyond a base's own radius for counting enemies on it |
| `cGodFortifyEnemyPlayers` | Enemy players on our bases that trigger fortify |
| `cGodFortifyThreatPercent` | Enemy-to-us power on our bases that also triggers fortify |
| `cGodFortifyQuietSeconds` | How long the bases must be quiet before fortify ends |
| `cGodFortifyTowersPerBase` | Towers per TC base while fortified |
| `cGodFallbackRatioPercent` | Enemy-to-us power on a base that triggers a fallback |
| `cGodFallbackReleasePercent` | Enemy-to-us power that releases the fallback |
| `cGodFallbackHoldSeconds` | How long a fallback lasts before it is released |
| `cGodScoreTower` / `cGodScoreTownCenter` / `cGodScoreFortress` / `cGodScoreHouse` | Weights scoring how defensible a base is |
| `cGodFallbackPriority` | Priority of the fallback plan (engine's primary defend is 10) |
| `cGodAssistRatioPercent` | Enemy-to-ally power on an ally base that needs help |
| `cGodAssistMinEnemyPower` | Minimum enemy power for an ally base to need help |
| `cGodAssistMaxSharePercent` | Most of our land army sent to help an ally |
| `cGodAssistMinUnits` | Fewest units worth sending to an ally |
| `cGodAssistMaxDistance` | Furthest ally base we will walk to help |
| `cGodAssistQuietSeconds` | How long an ally base must be safe before we come home |
| `cGodAssistPriority` | Priority of the assist plan |
| `cGodFrontTowerDistance` | How far out from the base centre the front tower goes |
| `cGodChokeMinDistance` / `cGodChokeMaxDistance` | Range from our main base where a choke is looked for |
| `cGodChokeMaxTilesPercent` | How much narrower than the path average an area must be to count as a choke |

## Caveats

- **"Under attack" means `gDefensivelyOverrun`.** That is the engine's serious-trouble
  signal, so the Wonder/Titan Gate gating only kicks in under real pressure.
- **The minor-god picks are a first pass.** They follow each god's documented focus, not
  measured results; revisit once telemetry shows which games are lost and why.
- **The tuning numbers are starting points.** Retreat, raid and push thresholds are the
  first things to adjust after a game.
- **The Titan depends on the tech and on favour.** `godResearchTitanTech` can only buy
  Secrets of the Titans when the game offers it and the favour is banked. Favour is exempt
  from `cGodTitanReservePercent` for that reason. When a stalemate is latched and the tech is
  not bought, the guard that held it is named in the log once a minute (`Titan held: …`) with
  the bank beside it, so a run that never reaches a Titan says which guard held it and what
  the bank looked like at the time. Nothing holds a favour floor for the tech, though: the
  army's myth units keep spending it, so a run can still stall here for a long time.
- **Choke detection is a heuristic.** The engine has no "choke" concept, so `godFindChoke`
  infers one from the area graph: the narrowest area on the path to the enemy. On an open map
  it falls back to a point on the straight line, which is not really a choke. Judged from its
  own log lines.
- **The team-game thresholds are a first pass.** `cGodFortify*`, `cGodFallback*`, `cGodAssist*`
  and `cGodChoke*` are starting points, tuned from team-game telemetry like the 1v1 numbers.
