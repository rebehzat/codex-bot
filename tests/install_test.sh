#!/usr/bin/env bash
# Plain-bash tests for install.sh. Each case gets a fresh HOME and an isolated
# PATH so the host's real codex/claude installs cannot affect auto-detection.
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$REPO/install.sh"
SRC="$REPO/skills/codex-bot"
SYS_PATH="/usr/bin:/bin"

pass=0
fail=0

ok() {
  pass=$((pass + 1))
  echo "PASS $1"
}

bad() {
  fail=$((fail + 1))
  echo "FAIL $1"
}

# setup <name>: fresh HOME, clean env, restricted PATH. Extra PATH stubs go in
# $TESTBIN (add fake `codex`/`claude` executables there to trigger detection).
setup() {
  TMPD="$(mktemp -d)"
  HOME="$TMPD/home"
  TESTBIN="$TMPD/bin"
  mkdir -p "$HOME" "$TESTBIN"
  PATH="$TESTBIN:$SYS_PATH"
  unset CODEX_HOME CLAUDE_CONFIG_DIR
  export HOME PATH
}

teardown() {
  rm -rf "$TMPD"
}

run_install() {
  bash "$INSTALL" "$@"
}

assert_link() { # <path>
  [ -L "$1" ] && [ "$(readlink "$1")" = "$SRC" ]
}

assert_no_link() { # <path>
  [ ! -L "$1" ] && [ ! -e "$1" ]
}

checksum_tree() { # <dir>: sorted "path hash" for files + link targets
  (cd "$1" && find . \( -type f -o -type l \) -print | sort | while read -r p; do
    if [ -L "$p" ]; then
      printf '%s link:%s\n' "$p" "$(readlink "$p")"
    else
      printf '%s %s\n' "$p" "$(md5sum <"$p" 2>/dev/null || md5 -q "$p")"
    fi
  done)
}

BLOCK_START='<!-- codex-bot:start -->'

# 1. Auto-detect: only ~/.codex present -> agents + codex, no claude.
setup auto
mkdir -p "$HOME/.codex"
run_install >"$TMPD/out"
rc=$?
if [ $rc -eq 0 ] \
  && assert_link "$HOME/.agents/skills/codex-bot" \
  && assert_link "$HOME/.codex/skills/codex-bot" \
  && assert_no_link "$HOME/.claude" \
  && grep -qF "$BLOCK_START" "$HOME/.codex/AGENTS.md" \
  && ! grep -qF "$BLOCK_START" "$HOME/.agents/AGENTS.md" 2>/dev/null; then
  ok "auto-detect installs agents+codex only"
else
  bad "auto-detect installs agents+codex only"
fi
teardown

# 2. --target all creates all three links and both pointers.
setup all
run_install --target all >"$TMPD/out"
rc=$?
if [ $rc -eq 0 ] \
  && assert_link "$HOME/.agents/skills/codex-bot" \
  && assert_link "$HOME/.codex/skills/codex-bot" \
  && assert_link "$HOME/.claude/skills/codex-bot" \
  && grep -qF "$BLOCK_START" "$HOME/.codex/AGENTS.md" \
  && grep -qF "$BLOCK_START" "$HOME/.claude/CLAUDE.md"; then
  ok "--target all installs everything"
else
  bad "--target all installs everything"
fi
teardown

# 3. Re-run is idempotent: byte-identical files, exactly one block.
setup idem
mkdir -p "$HOME/.codex"
run_install >/dev/null
checksum_tree "$HOME" >"$TMPD/before"
run_install >/dev/null
checksum_tree "$HOME" >"$TMPD/after"
count="$(grep -cF "$BLOCK_START" "$HOME/.codex/AGENTS.md")"
if cmp -s "$TMPD/before" "$TMPD/after" && [ "$count" -eq 1 ]; then
  ok "re-run is idempotent"
else
  bad "re-run is idempotent"
fi
teardown

# 4. Existing content preserved byte-for-byte across install + uninstall.
setup preserve
mkdir -p "$HOME/.codex"
printf 'my own rules\n\nkeep me\n' >"$HOME/.codex/AGENTS.md"
cp "$HOME/.codex/AGENTS.md" "$TMPD/orig"
run_install >/dev/null
run_install --uninstall >/dev/null
if cmp -s "$TMPD/orig" "$HOME/.codex/AGENTS.md"; then
  ok "content preserved across install+uninstall"
else
  bad "content preserved across install+uninstall"
fi
teardown

# 5. Legacy marker block is migrated in place.
setup legacy
mkdir -p "$HOME/.codex/skills"
cat >"$HOME/.codex/AGENTS.md" <<'EOF'
before

<!-- codex-bot -->
old pointer text
<!-- /codex-bot -->

after
EOF
cp "$HOME/.codex/AGENTS.md" "$TMPD/legorig"
run_install >/dev/null
if [ "$(grep -cF "$BLOCK_START" "$HOME/.codex/AGENTS.md")" -eq 1 ] \
  && ! grep -qF '<!-- codex-bot -->' "$HOME/.codex/AGENTS.md" \
  && ! grep -q 'old pointer text' "$HOME/.codex/AGENTS.md" \
  && head -1 "$HOME/.codex/AGENTS.md" | grep -q 'before' \
  && tail -1 "$HOME/.codex/AGENTS.md" | grep -q 'after'; then
  ok "legacy marker migrated"
else
  bad "legacy marker migrated"
fi
teardown

# 6. Refuses to replace a real directory.
setup realdir
mkdir -p "$HOME/.codex/skills/codex-bot/inner"
touch "$HOME/.codex/skills/codex-bot/inner/file"
run_install --target codex >"$TMPD/out" 2>&1
rc=$?
if [ $rc -ne 0 ] && [ -d "$HOME/.codex/skills/codex-bot/inner" ] \
  && [ ! -L "$HOME/.codex/skills/codex-bot" ]; then
  ok "refuses real directory"
else
  bad "refuses real directory"
fi
teardown

# 7. --force backs up a real directory then links.
setup force
mkdir -p "$HOME/.codex/skills/codex-bot/inner"
touch "$HOME/.codex/skills/codex-bot/inner/file"
run_install --target codex --force >"$TMPD/out"
rc=$?
backup_count="$(find "$HOME/.codex/skills" -maxdepth 1 -name 'codex-bot.backup-*' -type d | wc -l | tr -d ' ')"
backup_file_count="$(find "$HOME/.codex/skills" -path '*codex-bot.backup-*/inner/file' | wc -l | tr -d ' ')"
if [ $rc -eq 0 ] && assert_link "$HOME/.codex/skills/codex-bot" \
  && [ "$backup_count" -eq 1 ] && [ "$backup_file_count" -eq 1 ]; then
  ok "--force backs up real directory"
else
  bad "--force backs up real directory"
fi
teardown

# 8. --dry-run changes nothing.
setup dry
mkdir -p "$HOME/.codex/skills/codex-bot"
touch "$HOME/.codex/existing"
printf 'user content\n' >"$HOME/.codex/AGENTS.md"
checksum_tree "$HOME" >"$TMPD/before"
run_install --target all --force --dry-run >"$TMPD/out"
rc=$?
checksum_tree "$HOME" >"$TMPD/after"
if [ $rc -eq 0 ] && cmp -s "$TMPD/before" "$TMPD/after" && grep -q 'dry-run' "$TMPD/out"; then
  ok "--dry-run changes nothing"
else
  bad "--dry-run changes nothing"
fi
teardown

# 9. Uninstall removes links and blocks; a foreign symlink is left alone.
setup uninst
mkdir -p "$HOME/.codex" "$HOME/other"
run_install --target all >/dev/null
ln -sfn "$HOME/other" "$HOME/.claude/skills/codex-bot"
run_install --uninstall --target all >"$TMPD/out" 2>&1
rc=$?
if [ $rc -eq 0 ] \
  && assert_no_link "$HOME/.agents/skills/codex-bot" \
  && assert_no_link "$HOME/.codex/skills/codex-bot" \
  && [ -L "$HOME/.claude/skills/codex-bot" ] \
  && [ "$(readlink "$HOME/.claude/skills/codex-bot")" = "$HOME/other" ] \
  && ! grep -qF "$BLOCK_START" "$HOME/.codex/AGENTS.md"; then
  ok "uninstall removes ours, leaves foreign symlink"
else
  bad "uninstall removes ours, leaves foreign symlink"
fi
teardown

# 10. CODEX_HOME override is honored.
setup override
mkdir -p "$TMPD/custom-codex"
CODEX_HOME="$TMPD/custom-codex" run_install --target codex >/dev/null
rc=$?
if [ $rc -eq 0 ] && assert_link "$TMPD/custom-codex/skills/codex-bot" \
  && grep -qF "$BLOCK_START" "$TMPD/custom-codex/AGENTS.md" \
  && assert_no_link "$HOME/.codex"; then
  ok "CODEX_HOME override honored"
else
  bad "CODEX_HOME override honored"
fi
teardown

# 11. Unknown option exits 2.
setup unknown
run_install --bogus >"$TMPD/out" 2>&1
rc=$?
if [ $rc -eq 2 ]; then
  ok "unknown option exits 2"
else
  bad "unknown option exits 2"
fi
teardown

# 12. --no-pointer installs the link but writes no instructions file.
setup nopointer
mkdir -p "$HOME/.codex"
run_install --target codex --no-pointer >/dev/null
rc=$?
if [ $rc -eq 0 ] && assert_link "$HOME/.codex/skills/codex-bot" \
  && [ ! -f "$HOME/.codex/AGENTS.md" ]; then
  ok "--no-pointer skips pointer"
else
  bad "--no-pointer skips pointer"
fi
teardown

echo "----------------------------------------"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
