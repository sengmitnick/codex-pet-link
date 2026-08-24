#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SWIFT_BIN="${CODEX_PET_LINK_SWIFT:-swift}"
CODEX_BIN="${CODEX_PET_LINK_CODEX:-codex}"
DATA_DIR="$HOME/Library/Application Support/CodexPetLink"
BIN_DIR="$DATA_DIR/bin"
COMMAND_DIR="$HOME/.local/bin"
INSTALLED_BIN="$BIN_DIR/codex-pet-link"
COMMAND_LINK="$COMMAND_DIR/codex-pet-link"

if [ "${CODEX_PET_LINK_SKIP_PLATFORM_CHECK:-0}" != "1" ]; then
  [ "$(uname -s)" = "Darwin" ] || { echo "Codex Pet Link currently requires macOS." >&2; exit 1; }
  command -v "$SWIFT_BIN" >/dev/null 2>&1 || { echo "Swift is required. Install Xcode Command Line Tools first." >&2; exit 1; }
  command -v "$CODEX_BIN" >/dev/null 2>&1 || { echo "Codex CLI is required." >&2; exit 1; }
fi

"$SWIFT_BIN" build -c release --package-path "$ROOT_DIR"
mkdir -p "$BIN_DIR" "$COMMAND_DIR"
install -m 755 "$ROOT_DIR/.build/release/codex-pet-link" "$INSTALLED_BIN.new"
mv -f "$INSTALLED_BIN.new" "$INSTALLED_BIN"

if [ -e "$COMMAND_LINK" ] && [ ! -L "$COMMAND_LINK" ]; then
  echo "Refusing to replace existing file: $COMMAND_LINK" >&2
  exit 1
fi
ln -sfn "$INSTALLED_BIN" "$COMMAND_LINK"

"$CODEX_BIN" plugin marketplace add "$ROOT_DIR" >/dev/null 2>&1 || true
"$CODEX_BIN" plugin remove codex-pet-link@codex-pet-link >/dev/null 2>&1 || true
"$CODEX_BIN" plugin add codex-pet-link@codex-pet-link >/dev/null

"$INSTALLED_BIN" ensure
"$INSTALLED_BIN" doctor

echo "Codex Pet Link installed. Start a new Codex task so the plugin hooks are loaded."
