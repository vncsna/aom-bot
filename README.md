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

Copy `game/` into the game's local mod folder, keeping the mod name `CustomBot`:

```
…/Games/Age of Mythology Retold/<steam-id>/mods/local/CustomBot/game/…
```

Then pick **CustomBot** as an AI opponent in the skirmish lobby.

## Development notes

- Full setup, file locations, engine behaviour and reference docs live in
  [`AGENTS.md`](AGENTS.md).
- Changes are tracked in the commit history.

## Legal

Age of Mythology: Retold and all associated game assets, documentation and scripting
APIs are the property of their respective owners. This repository contains only
original mod code; proprietary game material is excluded via `.gitignore`.
