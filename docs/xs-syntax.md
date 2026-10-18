# XS Syntax Notes

XS is the BANG engine's scripting language; `custom_bot.xs` and the base game's AI
scripts are written in it. The authoritative grammar is the game's own
`BANG_Documentation/XS documentation/XS language syntax.pdf` (proprietary, not tracked
here). This file is the working subset the bot relies on, plus the parser traps that have
actually bitten us.

Every rule below was verified against the shipped base-game scripts under `game/ai/`.
Where this file and those scripts disagree, the scripts are right — fix this file.

## Switch statements

Each `case` body must be a braced block. A one-liner with a trailing `break` does not
parse:

```c
// Wrong. XS: Error 0230: expected 'case' or 'default' and found 'break'.
switch (cMyCiv)
{
	case cCivZeus: customSetMinorGods(a, b, c); break;
}

// Right.
switch (cMyCiv)
{
	case cCivZeus:
	{
		customSetMinorGods(a, b, c);
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
`custom_bot.xs` fails with `Error 0172: '<name>' is not a valid operator`. There is no way
to reach it from here: use an `extern`-declared equivalent, a strategy flag, or a rule
instead.

Functions are different — one defined in an included file is visible, so the only ordering
rule is the same-file one above.

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
  `custom_bot.xs`, called by `core/main.xs`.
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
| `0165` | `high level parseExpr2 failed` | Follows `0172`. |
| `0047` | `could not parse the code for '<function>'` | Follows a syntax error inside that function. |
| — | `could not compile file 'custom_bot.xs'` | Follows any of the above; the bot does not load. |

## Before running a change

The engine compiles XS only at match start and reports **one error at a time**, so a typo
costs a full game launch to find. Check these first:

1. Every `switch` case body is braced.
2. Every function is defined before its first use (or declared `mutable`).
3. Every global referenced is `extern`-declared or defined in this file.
4. Braces, parentheses and brackets balance.
5. Every engine function, constant and global exists — cross-check against the base-game
   scripts and the generated `temp/Logs/MythAIConstantsPlayer1.txt`.
6. Tabs for indentation, no trailing whitespace (see `.editorconfig`).
