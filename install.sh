#!/usr/bin/env bash
# Wire the live Age of Mythology: Retold mod folder to this checkout.
#
# The repository is the source of truth; the game's local mod directory gets
# symlinks back into it, so edits here reach the game without copying.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_DATA="$HOME/.local/share/Steam/steamapps/compatdata/1934680/pfx/drive_c/users/steamuser/Games/Age of Mythology Retold"

if [[ ! -d "$USER_DATA" ]]; then
	echo "Game user data not found at:" >&2
	echo "  $USER_DATA" >&2
	echo "Launch Age of Mythology: Retold at least once, then re-run." >&2
	exit 1
fi

# The Steam account ID is the numeric directory under the game's user data.
shopt -s nullglob
accounts=("$USER_DATA"/[0-9]*)
if ((${#accounts[@]} == 0)); then
	echo "No Steam account directory found under:" >&2
	echo "  $USER_DATA" >&2
	exit 1
fi
if ((${#accounts[@]} > 1)); then
	echo "Multiple accounts found; using ${accounts[0]}" >&2
fi
ACCOUNT="${accounts[0]}"

MOD="$ACCOUNT/mods/local/CustomBot"
SCENARIO="$ACCOUNT/scenario"

mkdir -p "$MOD/game/ai/personalities" "$MOD/.vscode" "$SCENARIO"

ln -sfn "$REPO/game/ai/custom_bot.xs"                         "$MOD/game/ai/custom_bot.xs"
ln -sfn "$REPO/game/ai/personalities/CustomBot.personality"   "$MOD/game/ai/personalities/CustomBot.personality"
ln -sfn "$REPO/game/ai/personalities/personalities_mods.xml"  "$MOD/game/ai/personalities/personalities_mods.xml"
ln -sfn "$REPO/.vscode/settings.json"                         "$MOD/.vscode/settings.json"

# The Scenario Editor opens …/scenario/ by default.
ln -sfn "$REPO/game/ai/custom_bot.xs" "$SCENARIO/custom_bot.xs"

echo "Linked CustomBot into:"
echo "  $MOD"
echo "  $SCENARIO/custom_bot.xs"
