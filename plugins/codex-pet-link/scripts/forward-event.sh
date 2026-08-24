#!/bin/sh
set -eu

EVENT_NAME="${1:-}"
BIN="${CODEX_PET_LINK_BIN:-$HOME/Library/Application Support/CodexPetLink/bin/codex-pet-link}"
[ -n "$EVENT_NAME" ] || exit 0
[ -x "$BIN" ] || exit 0
"$BIN" hook "$EVENT_NAME" >/dev/null 2>&1 || true
exit 0
