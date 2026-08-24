#!/bin/sh
set -eu

BIN="${CODEX_PET_LINK_BIN:-$HOME/Library/Application Support/CodexPetLink/bin/codex-pet-link}"
[ -x "$BIN" ] || exit 0
"$BIN" ensure >/dev/null 2>&1 || true
"$BIN" hook SessionStart >/dev/null 2>&1 || true
exit 0
