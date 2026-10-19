# AGENTS.md — AoM Retold God Bot Project

This document is the primary reference for AI agents and LLMs working on this project.
It describes the project structure, file locations, game engine constraints, and the
authoritative sources for all relevant documentation.

---

## Project Overview

A win-at-all-costs AI bot mod for **Age of Mythology: Retold** (Steam App ID `1934680`),
running on Linux via **Steam Proton** (Wine). The bot is authored in **XS** (eXternal
Scripting), the BANG engine's built-in scripting language, and is installed as a **local mod**.

---

## How Requirements Are Handled

Requirements arrive as plain-language descriptions of desired behaviour, not as specs.
Treat them as intent, not text: reorganize, merge, split and rewrite them into a coherent
design, and document that design — never a transcript of the request. The goal is to
achieve the behaviour, not to record how it was dictated.

---

## Complexity Budget

`god_bot.xs` grows by accretion unless it is capped. These are ceilings, not targets.

| Metric | Limit |
|---|---|
| `game/ai/god_bot.xs` lines | 1,500 |
| `rule` blocks (monitors) | 10 |
| `const` declarations | 30 |
| File-scoped `gGod*` globals | 20 |
| Custom plans that can own the land army | 0 |
| Army-posture states | 1 boolean |
| Work in the strategy `mUpdateFunc` | O(1) |
| Fields in the `[GBOT]` line | 20 |

The invariants behind the numbers:

- The engine's `gPrimaryLandDefendPlan` owns the land army by default. At most one
  custom plan may claim it at a time, and it must release on its own.
- The per-second strategy update does not loop over players × bases and does not run
  per-base KB queries. Periodic work belongs in a `rule` with a `minInterval`.
- No plan is created at a point that has not been path-validated.
- A new monitor, plan, or tunable replaces an existing one. If it cannot, the same
  change raises this budget and says why.
- A behaviour change names the piece it removes. "It was easier to add a plan" is not
  a reason.

`scripts/check_budget.py` enforces the countable limits in CI beside
`scripts/check_xs.py`.

---

## Documentation Conventions

Docs that describe this bot directly are prefixed `god-bot-` — for example
`docs/god-bot-design.md` and `docs/god-bot-minor-gods.md`. General engine material
that would apply to any bot keeps its own name, for example
`docs/ai-architecture.md`.

---

## Platform Notes (Immutable)

- **OS:** Linux
- **Runtime:** Steam Proton (Wine). The game sees a Windows filesystem emulated via Wine
  prefix under `~/.local/share/Steam/steamapps/compatdata/1934680/pfx/`.
- **Drive Mapping (Proton):**
  - `C:` → `…/compatdata/1934680/pfx/drive_c/`
  - `S:` → `~/.local/share/Steam/` (Steam install root)
  - `Z:` → `/` (Linux root)
- **Game Install Dir (Linux):**
  `~/.local/share/Steam/steamapps/common/Age of Mythology Retold/`
- **User Data Dir (Proton/Windows path):**
  `C:\users\steamuser\Games\Age of Mythology Retold\<steam-id>\`
- **User Data Dir (Linux path):**
  `~/.local/share/Steam/steamapps/compatdata/1934680/pfx/drive_c/users/steamuser/Games/Age of Mythology Retold/<steam-id>/`
- **Steam ID:** `<steam-id>` is your own Steam account ID. Every user-data path below
  contains it, so substitute your own when reproducing these locations.

---

## Canonical File Locations (Single Source of Truth)

This repository **is** the mod source. The live mod directory inside the Steam Proton
prefix holds nothing but symlinks back into this checkout, so edits here reach the game
immediately — nothing is copied or duplicated. Run `./scripts/install.sh` to create the mod
directory and wire those symlinks.

### Repository Root (source of truth)
```
<repo>/                                    ← this checkout
├── game/
│   └── ai/
│       ├── god_bot.xs                   ← Main entry-point script (edit this)
│       └── personalities/
│           ├── GodBot.personality       ← Points game engine to god_bot.xs
│           └── personalities_mods.xml   ← Registers "GodBot" in skirmish dropdown
└── .editorconfig                        ← Coding standards (tab=3 for .xs)
```

### Local Mod Root (symlinks → repo)
```
~/.local/share/Steam/steamapps/compatdata/1934680/pfx/drive_c/users/steamuser/
  Games/Age of Mythology Retold/<steam-id>/mods/local/GodBot/
```
The symlinks are absolute, so a moved or re-cloned checkout must be relinked by
re-running `scripts/install.sh`.

### Scenario Editor Symlink
```
…/<steam-id>/scenario/god_bot.xs  →  symlink to repo game/ai/god_bot.xs
```
The Scenario Editor file picker opens `…/scenario/` by default. The symlink means edits
in the repo propagate instantly without copying. `scripts/install.sh` creates it too.

### AI Debugger Config
```
…/<steam-id>/config/user.cfg
```
Contents:
```
aiDebug
AIvsAI
```
`aiDebug` enables the debug menu (`Alt+Shift+Q`) and XS debugger (`Alt+Shift+D`).
`AIvsAI` replaces player 1 with an AI, so the bot can play another bot unattended — the
bot's log then lands in `MythRetoldAIOutputPlayer1.txt`. Watch with `Ctrl+F1` (player 1)
and `Ctrl+F2` (player 2). Configs are read at startup only, so restart the game after
changing this file.

**Don't enable `aiDebugScript` for bot runs.** It makes the XS debugger breakpoint on any
XS warning, and a modded personality always trips one: `cPersonalityCurrent` is the
GodBot personality's index (`14` for `GodBot`, per `MythAIConstantsPlayer<N>.txt`), which no
case in the base game's `getCurrentPersonalityName()` matches, so it calls `aiEchoWarning`
("Unknown cPersonalityCurrent.") during startup. The breakpoint suspends the bot's script
there, so the bot does nothing for the whole match and its log stops on that line.
`aiHideWarningEchoes` hides the text but not the breakpoint. Use `aiDebugScript` only while
debugging the script, and resume the debugger instead of closing it.

---

## Test Scenarios

Located in `…/<steam-id>/scenario/`:
- `ai_test_map.mythscn` — Copy of the user's blank test map.
- `campaign_test_map.mythscn` — Copy of `fott02.mythscn` (populated skirmish map).
- `~testing.mythscn` — Auto-saved editor scratch file (created by the game engine).

`.mythscn` files are **binary** (magic header `l33t`, zlib-compressed chunk stream).
They are **not XML**. Create/edit them only via the in-game Scenario Editor.

---

## XS Script Architecture (Immutable Engine Behaviour)

The BANG engine calls XS scripts in the following order on match start:

```
Game Engine
  └─ loads GodBot.personality  →  reads <script>god_bot</script>
       └─ god_bot.xs           →  include "core/main.xs"
            └─ core/main.xs
                 ├─ preInit()     ← USER HOOK: overrides before engine setup
                 ├─ doStartupFlow()
                 ├─ initXSHandlers()
                 └─ prepareForInit()
                      └─ postInit()  ← USER HOOK: overrides after engine setup
```

**`preInit()`** — Override global variables and set a custom strategy. Runs before any
engine base-building or KB analysis.

**`postInit()`** — Tweak live plans/settings after the engine has completed startup.

Key override variables (all in `core/globals_override.xs`):
| Variable | Type | Description |
|---|---|---|
| `gOverrideMaxVillagerPop` | `int` | Cap on villager count |
| `gOverrideFarmCount` | `int` | Max farms to build |
| `gOverrideTargetPlayerID` | `int` | Force attack a specific player |
| `gOverrideClassicalMinorGod` | `int` | Force Classical age god choice |
| `gOverrideHeroicMinorGod` | `int` | Force Heroic age god choice |
| `gOverrideMythicMinorGod` | `int` | Force Mythic age god choice |
| `gInactiveAI` | `bool` | Set true to make AI do nothing |
| `setOverrideStrategy(fn)` | `void()` | Replace built-in strategy with custom one |

---

## Strategy System

Strategies are defined as `Strategy` structs with two lambda functions:

```c
Strategy myStrategy()
{
   Strategy s;
   s.mID   = cStrategySPCCustom;   // or cStrategyScenarioAttackWave
   s.mAge  = cAge1;
   s.mName = "My Strategy";

   s.mInitFunc = [](ref StrategyData data) -> bool
   {
      data.setFlag(cStrategyFlagAutomaticEco, true);
      data.setFlag(cStrategyFlagAutomaticVillagerTraining, true);
      data.setFlag(cStrategyFlagBuildHouses, true);
      data.addUnitToMaintain(cUnitTypeHoplite, 6);
      // ...
      return true;
   };

   s.mUpdateFunc = [](ref StrategyData data) -> bool
   {
      return true; // keep strategy alive
   };

   return s;
}

void myStrategySetup() { gStrategyManager.addStrategy(myStrategy()); }

void preInit()
{
   setOverrideStrategy(myStrategySetup);
}
```

Attack waves use `gAttackWave`:
```c
gAttackWave.setAttackStartTime(180);   // seconds before first attack
gAttackWave.setAttackInterval(120);    // seconds between waves
gAttackWave.setAttackSize(8);          // units per wave
gAttackWave.setMaxAttackSize(16);
gAttackWave.addAttackUnitType(cUnitTypeHoplite);
gAttackWave.setPlayerToAttack(1);
```

---

## Reference Documentation

### Authoring Bot Behavior
[`docs/ai-architecture.md`](docs/ai-architecture.md) explains how bot behavior is
expressed — the strategy system, `StrategyData` policy, attack waves, defend plans,
rules, build orders and overrides — with a translation cheat-sheet for turning plain
behavior descriptions into code. Start here when adding functionality.

[`docs/god-bot-design.md`](docs/god-bot-design.md) describes how the god bot is put
together and why — its goal, the powers it exploits, its architecture and behaviour.

### XS Language Notes
[`docs/xs-syntax.md`](docs/xs-syntax.md) records the XS constructs the bot uses and the
parser traps worth knowing — each rule verified against the shipped base-game scripts.
Read it before editing `god_bot.xs`; it is the practical companion to the official
language PDFs below.

There is no standalone XS compiler, so run `scripts/check_xs.py` before every game launch —
it statically checks the script against those rules, and
`scripts/tests/test_check_xs.py` keeps the checker honest. CI runs both without the game.

### Athens Syscalls (XS API)
Full Doxygen HTML reference for all AI/KB/XS syscalls. **Not tracked in this repo** — it is
extracted from the game's own `doxygen_retail.7z` and excluded via `.gitignore`. Extract
it locally (e.g. to `./athens-syscalls/`) and open `index.html` in a browser. Key files:
- `globals_func.html` — All available XS functions (alphabetical)
- `aifuncs_8cpp.html` — AI plan and unit management functions
- `aiplans_8cpp.html` — Plan creation and configuration

### Official BANG Documentation PDFs
```
~/.local/share/Steam/steamapps/common/Age of Mythology Retold/BANG_Documentation/
```
Relevant files:
- `AI documentation/How-to create your own skirmish AI.pdf`
- `AI documentation/AI dev environment setup.pdf`
- `AI documentation/What is allowed in AI scripts.pdf`
- `XS documentation/XS language syntax.pdf`
- `XS documentation/XS debugger.pdf`
- `Config documentation/Config basics.pdf`

### Base Game AI Scripts (read-only reference)
```
~/.local/share/Steam/steamapps/common/Age of Mythology Retold/game/ai/
├── chairon.xs                    ← Entry point used by ALL stock skirmish personalities
├── inactive_ai.xs                ← Example of a no-op AI
├── core/
│   ├── main.xs                   ← Engine startup sequence
│   ├── globals.xs                ← Personality-dependent compile-time constants
│   ├── globals_override.xs       ← Override hooks available to custom scripts
│   ├── setup.xs                  ← Build order and strategy initialization
│   ├── handlers.xs               ← XS event handlers
│   └── …
├── personalities/
│   ├── personalities.xml         ← Registers stock personalities (do NOT edit)
│   ├── attacker.personality      ← Example: aggressive personality
│   ├── defender.personality      ← Example: defensive personality
│   └── …
└── campaign/
    └── fott/                     ← Campaign AI scripts with attack wave examples
        ├── fott02_p2.xs          ← Good example: attack waves + naval + eco flags
        └── fott04_p3.xs          ← Good example: minimal gather-only bot
```

### VS Code XS Extension
Installed from:
```
~/.local/share/Steam/steamapps/common/Age of Mythology Retold/BANG_Documentation/vscodeextension/xs.vsix
```
Provides hover documentation for all XS syscalls.  
**Must be reinstalled after every game patch** (the extension does not auto-update).

---

## Personality Registration (Immutable Rules)

- Custom personalities **cannot** be added to `game/ai/personalities/personalities.xml`
  (base game file; overwritten by patches).
- Use `personalities_mods.xml` in the mod folder (additive; survives patches).
- The `<script>` tag value must match the `.xs` filename **without extension**.
- `nameID` and `descriptionID` must reference valid string table IDs from the game's
  internal stringtable. Using a stock ID (e.g. `STR_AI_PERS_ATTACKER`) causes the bot
  to appear with that name in the skirmish dropdown. A custom string table mod would be
  needed to show a truly custom name.
- `canBeRandomed` controls whether this personality is eligible when the player selects
  "Random" AI in the lobby.

---

## In-Game Debug Hotkeys

| Hotkey | Action |
|---|---|
| `Alt + Shift + Q` | Toggle AI Debug Menu |
| `Alt + Shift + D` | Toggle XS Debugger window |
| `Ctrl + F1` | Switch view to Player 1 |
| `Ctrl + F2` | Switch view to Player 2 |
| `Ctrl + Shift + F10` | Switch view to Mother Nature (player 0) |

AI constants file (generated at game launch when `aiDebug` is active):
```
…/Games/Age of Mythology Retold/temp/Logs/MythAIConstantsPlayer1.txt
```
Use this to resolve numeric constant IDs (e.g. what `cUnitTypeHoplite` resolves to).

---

## Bot Telemetry & Run Metadata

`godTelemetryMonitor` in `god_bot.xs` logs one metrics line every 30 seconds:

```
[GBOT] t=… age=… vills=… pop=cur/cap army=… food=… wood=… gold=… favor=… enemyAge=… enemyTitan=0|1 titans=… wonder=… state=hold|push underAttack=0|1 enemies=… allies=… defend=0|1
```

Where it lands (under the game's user data, `…/Games/Age of Mythology Retold/`):

| Path | Contents |
|---|---|
| `temp/Logs/MythRetoldAIOutputPlayer<N>.txt` | Per-player AI output, **UTF-16** — the `[GBOT]` lines live here |
| `temp/Logs/MythLog.txt` | General game log |
| `temp/Logs/PerformanceMetrics/*.csv` | Per-session FPS/tick metrics only (no gameplay data) |
| `<steam-id>/replays/Record GameN.mythrec` | Recorded games (binary, not parseable here) |

`scripts/parse_ai_log.py <log>` turns a player log into a table.

There is no XS file-write syscall, so `aiEcho` logging is the only telemetry channel.

### Saving run metadata

To let an agent reason about results later, capture per-match metadata:

- **Manual results sheet** — cheapest, works today: date, map, size, difficulty, our civ,
  opponent personality, opponent civ, result, duration, notes. This is
  [`docs/god-bot-record.md`](docs/god-bot-record.md), which also notes what each change was
  meant to do; add a row there after a match.
- **Telemetry log** — richest: run `scripts/archive_run.py [notes…]` right after a match.
  It keeps the bot's own `[GodBot]` events and `[GBOT]` telemetry and writes them to
  `runs/<stamp>-<map>.log`, under a header naming the map and both players (read from
  `MythLog.txt` and the `MythAIConstantsPlayer<N>.txt` files). `scripts/parse_ai_log.py`
  then reads the telemetry back out. The engine truncates the per-player log when the next
  session starts, so archive *before* starting another match — otherwise that run's
  telemetry is gone.
- **Replays** — full fidelity for a human, but binary; keep them for manual review.
