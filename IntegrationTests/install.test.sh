#!/bin/sh
set -eu

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
TEST_HOME="$TEST_ROOT/home"
TEST_BIN="$TEST_ROOT/bin"
TEST_LOG="$TEST_ROOT/codex.log"
mkdir -p "$TEST_HOME" "$TEST_BIN"

cat >"$TEST_BIN/swift" <<'SCRIPT'
#!/bin/sh
set -eu
PACKAGE_PATH=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "--package-path" ]; then PACKAGE_PATH="$2"; shift 2; else shift; fi
done
mkdir -p "$PACKAGE_PATH/.build/release"
cat >"$PACKAGE_PATH/.build/release/codex-pet-link" <<'HELPER'
#!/bin/sh
exit 0
HELPER
chmod +x "$PACKAGE_PATH/.build/release/codex-pet-link"
SCRIPT
chmod +x "$TEST_BIN/swift"

cat >"$TEST_BIN/codex" <<SCRIPT
#!/bin/sh
printf '%s\n' "\$*" >>"$TEST_LOG"
exit 0
SCRIPT
chmod +x "$TEST_BIN/codex"

for attempt in 1 2; do
  HOME="$TEST_HOME" PATH="$TEST_BIN:/usr/bin:/bin" \
    CODEX_PET_LINK_SKIP_PLATFORM_CHECK=1 \
    CODEX_PET_LINK_SWIFT="$TEST_BIN/swift" \
    CODEX_PET_LINK_CODEX="$TEST_BIN/codex" \
    sh scripts/install.sh
done

test -x "$TEST_HOME/Library/Application Support/CodexPetLink/bin/codex-pet-link"
test -L "$TEST_HOME/.local/bin/codex-pet-link"
test ! -e "$TEST_HOME/Library/LaunchAgents/com.rokid.codex-pet-link.plist"
grep -q 'plugin marketplace add' "$TEST_LOG"
grep -q 'plugin add codex-pet-link@codex-pet-link' "$TEST_LOG"
echo "install test passed"
