#!/usr/bin/env bash
# Validate skills/codex-bot/SKILL.md frontmatter:
# starts with ---, has a closing ---, name matches the directory, description
# is present, non-empty and <= 1024 chars.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="$REPO/skills/codex-bot"
SKILL="$SKILL_DIR/SKILL.md"

fail() {
  echo "validate_skill: $1" >&2
  exit 1
}

[ -f "$SKILL" ] || fail "$SKILL not found"
[ "$(head -n 1 "$SKILL")" = "---" ] || fail "SKILL.md must start with --- frontmatter"

awk -v dir="$(basename "$SKILL_DIR")" '
  NR == 1 { next }               # skip opening ---
  /^---$/ { closing = NR; exit }
  /^name:[[:space:]]*/ {
    sub(/^name:[[:space:]]*/, "")
    gsub(/^["'"'"']|["'"'"']$/, "")
    name = $0
  }
  /^description:[[:space:]]*/ {
    sub(/^description:[[:space:]]*/, "")
    gsub(/^["'"'"']|["'"'"']$/, "")
    desc = $0
  }
  END {
    if (!closing) { print "no closing --- in frontmatter"; exit 1 }
    if (name != dir) { print "name [" name "] != directory [" dir "]"; exit 1 }
    if (desc == "") { print "description missing or empty"; exit 1 }
    if (length(desc) > 1024) { print "description longer than 1024 chars"; exit 1 }
  }
' "$SKILL" || exit 1

echo "SKILL.md frontmatter OK"
