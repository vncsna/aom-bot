---
name: Validate
description: Run the bot's static checks and regression tests before launching the game.
---

Run from the repository root.

```sh
python3 scripts/validate_personalities.py
python3 scripts/check_xs.py
python3 scripts/tests/test_check_xs.py
python3 scripts/tests/test_archive_run.py
```

`scripts/check_xs.py` uses the game install to verify that the symbols the bot
references actually exist. Pass `--no-game` to run only the checks that work from the
repository alone — that is the set CI runs.
