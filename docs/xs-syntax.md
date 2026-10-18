# XS Syntax Notes

XS is the BANG engine's scripting language; `god_bot.xs` and the base game's AI
scripts are written in it. The authoritative grammar is the game's own
`BANG_Documentation/XS documentation/XS language syntax.pdf` (proprietary, not tracked
here). This file is the working subset the bot relies on, plus the parser traps that have
actually bitten us.

The engine compiles XS only at match start and there is no standalone compiler, so check
changes with `scripts/check_xs.py` (see [Checking a change](#checking-a-change)) before
launching the game.

Every rule below was verified against the shipped base-game scripts under `game/ai/`.
Where this file and those scripts disagree, the scripts are right — fix this file.

## Switch statements

Each `case` body must be a braced block. A one-liner with a trailing `break` does not
parse:

```c
// Wrong. XS: Error 0230: expected 'case' or 'default' and found 'break'.
switch (cMyCiv)
{
	case cCivZeus: godSetMinorGods(a, b, c); break;
}

// Right.
switch (cMyCiv)
{
	case cCivZeus:
	{
		godSetMinorGods(a, b, c);
		break;
	}
}
```

A bad `case` aborts its whole function (error `0047`), and then the whole file
(`could not compile file`), so one bad case stops the bot from loading at all.

## Functions

- **A function must be declared before its first use.** XS resolves symbols in a single
  pass, so calling something defined further down the file fails with
  `Error 0310: invalid symbol lookup for '<name>'`. Keep callees above callers.
- **Forward declarations** exist for when you cannot: declare a `mutable` stub with a body,
  then define the real function later. This is how `core/core.xs` declares `preInit()` and
  `postInit()` before the engine calls them.

  ```c
  mutable void setupPatrolPlans(vector gatherPoint = cInvalidVector) {}
  ```

- **Default arguments are supported**: `void build(int type = -1, vector at = cInvalidVector)`.
- **Every value parameter must have a default**: the parser reads a parameter as a
  declaration, so it demands its `=`.

  ```c
  // Wrong. XS: Error 0016: expected '=' and found ')' (you must initialize all
  // variables to a literal or const value).
  bool near(vector location)

  // Also wrong: expected '=' and found ','.
  int near(vector location, float radius = 60.0)

  // Right.
  int near(vector location = cInvalidVector, float radius = 60.0)
  ```

  Only a `ref` parameter is left bare: `void defend(ref float powerToDefendWith)`.
- **`ref` parameters** pass by reference: `void pick(ref int techID)`.
- **Lambdas** take the form `[](ref StrategyData data) -> bool { … };`.

## Globals and visibility

A global is **file-scoped unless declared `extern`**. The shared ones live in
`core/globals.xs`:

```c
extern int gHouseUnit = -1;
```

A plain `int gFoo = -1;` in another file — for example `gTitanGateCurrentState` in
`core/godpowers/godpowers.xs` — is private to that file. Referencing it from
`god_bot.xs` fails with `Error 0172: '<name>' is not a valid operator`. There is no way
to reach it from here: use an `extern`-declared equivalent, a strategy flag, or a rule
instead.

Functions are different — one defined in an included file is visible, so the only ordering
rule is the same-file one above.

## Expressions and conditions

A comparison whose **left** operand multiplies or divides (`*`, `/`) must be parenthesised
when it sits inside a compound condition (`&&` or `||`):

```c
// Rejected: Error 0308: illogical or invalid expression.
if (lostPop > 0 && lostPop * 100 >= sample * percent)

// Accepted — and this is what every shipped instance looks like.
if (wantedPop != 0 && (navyPop * 0.8) > enemyWarships)
```

The rule does not cover the rest:

- `+` and `-` on the left are fine:
  `lastUpdateTime + nextTargetUpdateInterval <= xsGetTime() || …` is in
  `core/economy/economy.xs`.
- Arithmetic on the **right** needs no parentheses: `a < b * 1.6 && a > b * 0.4` is in
  `core/economy/trade.xs`.
- A lone comparison without `&&` or `||` is fine either way.

Cleaner still, and what this repo prefers: compute into a local, then compare two simple
values.

```c
int lostPercent = (lostPop * 100) / sample;
if (lostPercent >= cGodRetreatLossPercent)
```

## Types

`bool`, `int`, `float`, `string`, `vector`, with `const` for compile-time constants. A
variable can be declared in a `for` initialiser: `for (int i = 0; i < n; i++)`.

## Arrays

```c
int[] units = new int(0, -1);   // capacity 0, pre-filled with -1
units.add(42);
int n = units.size();
```

## Strings

`+` concatenates and converts numbers and vectors implicitly:

```c
aiEcho("attack at " + planLoc + " in " + xsGetTime() + "s");
```

## Rules

```c
rule myMonitor
inactive
minInterval 30
{
	// …
}
```

Rules are switched on from `postInit()` with `xsEnableRule` and controlled with
`xsDisableRule`, `xsIsRuleEnabled` and `xsRuleIgnoreIntervalOnce`. `minInterval` is in
seconds.

## Engine hooks the bot uses

- `preInit()` runs before engine setup and `postInit()` after. Both are plain functions in
  `god_bot.xs`, called by `core/main.xs`.
- `setOverrideStrategy(setupFunc)` in `preInit()` replaces the stock strategy; the setup
  function adds a `Strategy` to `gStrategyManager`.
- A `Strategy` carries `mInitFunc` and `mUpdateFunc` lambdas. `mUpdateFunc` runs about once
  a second (driven by the engine's `strategyMonitor`, `minInterval 1`); returning `false`
  ends the strategy.

## Parser errors seen so far

| Code | Message | Meaning |
|---|---|---|
| `0230` | `expected 'case' or 'default' and found 'break'` | A `switch` case body is not braced. |
| `0221` | `parseSwitch failed` | Follows `0230`. |
| `0310` | `invalid symbol lookup for '<name>'` | A function is called before it is declared. |
| `0052` | `could not parse the code for THEN block` | Follows `0310` inside an `if` body. |
| `0135` | `parseConditionDecl failed` | Follows `0310` or `0172` inside a condition. |
| `0172` | `'<name>' is not a valid operator` | A symbol is not visible — usually a global that is not `extern`. |
| `0165` | `high level parseExpr2 failed` | Follows `0172` or `0308`. |
| `0308` | `illogical or invalid expression` | A comparison's left operand is an unparenthesised `*` or `/` inside a compound condition. |
| `0016` | `expected '=' and found ','` / `… found ')'` | A parameter has no default value. |
| `0045` | `could not parse parameter declaration` | Follows `0016`. |
| `0047` | `could not parse the code for '<function>'` | Follows a syntax error inside that function. |
| — | `could not compile file 'god_bot.xs'` | Follows any of the above; the bot does not load. |

## Checking a change

The engine compiles XS only at match start and reports **one error at a time**, so a typo
costs a full game launch to find. There is no standalone XS compiler to run instead — the
official VS Code extension only highlights syntax and shows hover docs — so this repo ships
its own checker:

```
scripts/check_xs.py            # every check, needs the game installed
scripts/check_xs.py --no-game  # structural checks only (used by CI)
```

It enforces the rules above: balanced delimiters, braced `switch` cases, definition order,
parameter initialisation, `extern` globals, known constants, functions and rule names, and
the multiply-or-divide-on-the-left trap, including conditions split across lines.
`scripts/tests/test_check_xs.py` holds one regression case per kind of error.

Engine constants and syscalls are never defined in XS, so the checker learns them from
what the shipped scripts use (plus `MythAIConstantsPlayer1.txt` when it exists).

Two things it cannot do, so keep an eye on them:

1. A genuine constant or syscall that no base-game script uses is reported as unknown.
   Confirm it in the Athens syscall reference before working around the warning.
2. Tabs for indentation and no trailing whitespace (see `.editorconfig`) are style, not
   syntax, and are not checked.
