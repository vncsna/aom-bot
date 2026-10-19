---
name: Review
description: Archive the last match's bot telemetry and read it back as a table.
---

The engine truncates the per-player AI log when the next session starts, so archive
*before* launching another match.

Archive the last match, optionally with notes about it:

```sh
python3 scripts/archive_run.py [notes…]
```

This keeps only the bot's `[GBOT]` and `[GodBot]` lines and writes
`runs/<stamp>-<map>.log` with a header naming the map and both players.

Read the newest archive back as a table:

```sh
python3 scripts/parse_ai_log.py "$(ls -t runs/*.log | head -1)"
```

Record the result in `docs/god-bot-record.md`.
