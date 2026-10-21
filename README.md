## AoM Retold — God Bot

A win-at-all-costs AI bot mod for **Age of Mythology: Retold** (Steam App ID `1934680`),
written in **XS** — the BANG engine's built-in scripting language.

It installs as a **local mod** and appears in the skirmish AI dropdown as `GodBot`. The
goal is simple: **always win** a 1v1 against the stock personalities, using powers a human
player does not have — it reads the whole board without scouting. See
[`docs/god-bot-design.md`](docs/god-bot-design.md) for the goal, the powers it exploits and
how it is built.

## Installing

The repository is the source of truth; the game's local mod folder just holds symlinks
back into it:

```sh
./scripts/install.sh
```

This finds your Steam account directory under the Proton prefix and wires the mod folder
and Scenario Editor symlink. It is idempotent — re-run it after moving the checkout, since
the symlinks are absolute. Then pick **GodBot** as an AI opponent in the skirmish lobby.

## Docs

- [`AGENTS.md`](AGENTS.md) — setup, file locations, engine behaviour and references.
- [`docs/ai-architecture.md`](docs/ai-architecture.md) — how bot behavior is expressed.
- [`docs/xs-syntax.md`](docs/xs-syntax.md) — XS syntax notes and parser traps.
- [`docs/god-bot-design.md`](docs/god-bot-design.md) — the bot's design and goal.
- [`docs/god-bot-minor-gods.md`](docs/god-bot-minor-gods.md) — the minor-god picks and matchups.
- [`docs/god-bot-record.md`](docs/god-bot-record.md) — results and what each change was meant to do.

## Postmortem

The goal was **always win**, and the honest result is a bot that is regularly ahead on
age, economy and army in the recorded matches and still loses or stalls. The strategy
is not the interesting failure. The loop around it is: one match costs 30–60 minutes,
and until it finishes nothing in this repository can tell you whether a change helped.

### What went wrong

| Failure | What it cost | What is needed |
|---|---|---|
| **The feedback loop is slow and reports the wrong thing.** One skirmish takes 30–60 minutes, `[GBOT]` is a 30s snapshot of state rather than of decisions, favour is not in it at all, and the log is truncated when the next session starts. | A tuning constant needed a whole evening to earn a verdict; one diagnosis rested on the *absence* of a line across 44 minutes, and a missed archive threw the match away. | A fixed scenario (map, opponent, start conditions, minor gods) run as AIvsAI at the fastest speed and judged after ~10 minutes, with the metrics line carrying favour and the tech state, a reason logged whenever a gate changes its answer (`gate titan blocked=favour`), and archiving automatic on match end. |
| **Nothing prevents a regression.** Team-game work — the fortify stance, the base fallback, the ally assist, the choke, the per-base threat count, the front tower — all landed on the same land army the 1v1 plan uses. | The 1v1 baseline got worse while team coverage improved; the layer competed with the engine and one plan at an unreachable point froze the army. All of it was deleted in `015519c` and `112e452`. | A frozen baseline run per change, invariants read from the log (Titan under way after Mythic, no warship on a land map, the gate reopening on cadence), and never one commit that moves 1v1 and team behaviour at once. |
| **Rules are checked for syntax, not for agreement.** `check_xs.py` proves the symbols exist. It cannot see that the favour hold destroys myth plans every 10s while `militaryManager` recreates them every 30s, so the 50-favour bank could never form. | Three matches were spent on "why is there no Titan" before that contradiction was visible, and only because favour happened to be the one resource missing from the telemetry. | Declare what each rule reads and writes, what gates the bot has, and who owns the army; fail CI on a gate no state satisfies, two rules driving the same flag, or a plan with no releaser. |
| **Effort went into proxies, not the win condition.** Push/slow flapping, raid micro, tower upgrades and cadence constants got the time, while most recorded matches ended at `titans=0 wonder=0`, and the complexity budget only arrived after 10 rules and 29 constants had to be deleted wholesale. | A lead that was never converted is the normal shape of a loss here, the fixes aimed elsewhere, and the rescue deletion cost more than starting under the ceiling would have. | Measure the endgame first (Mythic → first Titan or Wonder), treat an unconverted lead as the primary bug, keep `check_budget.py` in CI from day one, and let a row without an `Observed` value block the next change. |

### What worked

- The archive, `parse_ai_log.py` and the `Observed` column turned "it felt bad" into the
  diagnoses above; every failure listed here is quoted from
  [`docs/god-bot-record.md`](docs/god-bot-record.md).
- The complexity budget and `scripts/check_budget.py`, once they existed.
- Giving the army back to the engine: fewer rules, no frozen army, one owner.
- Writing each change's expected effect down before the run — the rows that say "no
  effect" are the ones that saved time later.

The order for the next iteration is the loop, not the strategy: a short, repeatable test
with honest telemetry, invariants that catch a regression in one run, a static check that
the rules agree, and the endgame measured before anything else is tuned.

## Legal

Released under the [MIT License](LICENSE).

Age of Mythology: Retold and all associated game assets, documentation and scripting
APIs are the property of their respective owners. This project is unofficial and not
affiliated with or endorsed by the game's developer or publisher. It requires a
legitimate copy of the game to run and ships no game material — proprietary assets
(extracted API documentation, `.mythscn` maps) are excluded via `.gitignore`.
