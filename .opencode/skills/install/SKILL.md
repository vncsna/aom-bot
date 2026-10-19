---
name: Install
description: Link the GodBot mod into the game's local mod folder.
---

Run from the repository root:

```sh
./scripts/install.sh
```

It finds the Steam account directory under the Proton prefix and wires symlinks from
the game's local mod folder and the Scenario Editor back into this checkout, so edits
here reach the game without copying. It is idempotent — re-run it after moving or
re-cloning the checkout, since the symlinks are absolute.

Then pick **GodBot** as an AI opponent in the skirmish lobby.
