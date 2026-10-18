## AoM Retold — God Bot

A custom AI bot mod for **Age of Mythology: Retold** (Steam App ID `1934680`), written
in **XS** — the BANG engine's built-in scripting language.

It installs as a **local mod** and appears in the skirmish AI dropdown as `GodBot`.
The goal is a personality that wins 1v1 against the stock personalities on the same maps
at the same difficulty; see [`docs/god-bot-design.md`](docs/god-bot-design.md) for
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

## Legal

Released under the [MIT License](LICENSE).

Age of Mythology: Retold and all associated game assets, documentation and scripting
APIs are the property of their respective owners. This project is unofficial and not
affiliated with or endorsed by the game's developer or publisher. It requires a
legitimate copy of the game to run and ships no game material — proprietary assets
(extracted API documentation, `.mythscn` maps) are excluded via `.gitignore`.
