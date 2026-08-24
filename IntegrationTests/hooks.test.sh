#!/bin/sh
set -eu

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
FAKE_BIN="$TEST_ROOT/codex-pet-link"

cat >"$FAKE_BIN" <<'SCRIPT'
#!/bin/sh
echo "helper output that hooks must hide"
echo "helper error that hooks must hide" >&2
exit 9
SCRIPT
chmod +x "$FAKE_BIN"

OUTPUT="$(printf '%s' '{"session_id":"s1"}' | CODEX_PET_LINK_BIN="$FAKE_BIN" plugins/codex-pet-link/scripts/forward-event.sh UserPromptSubmit 2>&1)" || {
  echo "forward-event hook must fail open" >&2
  exit 1
}
test -z "$OUTPUT"

OUTPUT="$(printf '%s' '{"session_id":"s1"}' | CODEX_PET_LINK_BIN="$FAKE_BIN" plugins/codex-pet-link/scripts/ensure-running.sh 2>&1)" || {
  echo "SessionStart hook must fail open" >&2
  exit 1
}
test -z "$OUTPUT"
echo "hook test passed"
