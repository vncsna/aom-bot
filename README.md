# AoM Retold — Custom Bot

A custom AI bot mod for **Age of Mythology: Retold** (Steam App ID `1934680`), written
in **XS** — the BANG engine's built-in scripting language.

The bot is installed as a **local mod** and appears in the skirmish AI dropdown as
`CustomBot`.

## Layout

```
game/ai/
├── custom_bot.xs                     Main entry-point script
└── personalities/
    ├── CustomBot.personality         Points the engine at custom_bot.xs
    └── personalities_mods.xml        Registers CustomBot in the skirmish dropdown
.vscode/settings.json                 XS coding standards (tab=3, rulers at column 130)
```

`custom_bot.xs` includes the base game's `core/main.xs`, which drives the engine
startup flow and exposes two override hooks:

| Hook | Runs | Use it for |
|---|---|---|
| `preInit()` | Before engine base-building and KB analysis | Overriding globals, installing a custom strategy |
| `postInit()` | After engine startup completes | Tweaking live plans, build orders and army plans |

## Installing

The repository is the source of truth; the game's local mod folder just holds symlinks
back into it. Point them at your checkout with:

```sh
./install.sh
```

This finds your Steam account directory under the Proton prefix and creates the mod
folder plus the Scenario Editor symlink. It is idempotent — re-run it after cloning or
moving the checkout, since the symlinks are absolute.

Then pick **CustomBot** as an AI opponent in the skirmish lobby.

## Current limitations

- The personality reuses stock string IDs (`STR_AI_PERS_ATTACKER`) and the aggressive
  portrait, so it appears as **"Attacker"** in the lobby. A custom stringtable + icon mod
  would be needed for a distinct name.

## Development notes

- Full setup, file locations, engine behaviour and reference docs live in
  [`AGENTS.md`](AGENTS.md).
- How bot behavior is expressed (strategies, attack waves, rules, overrides) and how to
  translate behavior into code: [`docs/ai-architecture.md`](docs/ai-architecture.md).
- Changes are tracked in the commit history.

## Legal

Released under the [MIT License](LICENSE).

Age of Mythology: Retold and all associated game assets, documentation and scripting
APIs are the property of their respective owners. This project is unofficial and not
affiliated with or endorsed by the game's developer or publisher. It requires a
legitimate copy of the game to run and ships no game material — proprietary assets
(extracted API documentation, `.mythscn` maps) are excluded via `.gitignore`.
