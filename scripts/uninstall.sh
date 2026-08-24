#!/bin/sh
set -eu

CODEX_BIN="${CODEX_PET_LINK_CODEX:-codex}"
DATA_DIR="$HOME/Library/Application Support/CodexPetLink"
INSTALLED_BIN="$DATA_DIR/bin/codex-pet-link"
COMMAND_LINK="$HOME/.local/bin/codex-pet-link"

if [ -x "$INSTALLED_BIN" ]; then "$INSTALLED_BIN" stop >/dev/null 2>&1 || true; fi
"$CODEX_BIN" plugin remove codex-pet-link@codex-pet-link >/dev/null 2>&1 || true
"$CODEX_BIN" plugin marketplace remove codex-pet-link >/dev/null 2>&1 || true

if [ -L "$COMMAND_LINK" ]; then rm "$COMMAND_LINK"; fi
case "$DATA_DIR" in
  "$HOME/Library/Application Support/CodexPetLink") rm -rf "$DATA_DIR" ;;
  *) echo "Refusing unexpected data path: $DATA_DIR" >&2; exit 1 ;;
esac

echo "Codex Pet Link removed. Codex sessions were not touched."
