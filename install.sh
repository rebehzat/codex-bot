#!/usr/bin/env bash
# Install or uninstall the codex-bot skill for supported agents.
# See README.md for the interface. Portable to bash 3.2 (macOS) and bash 5.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  install.sh [--target agents|codex|claude|all]... [--no-pointer] [--force] [--dry-run]
  install.sh --uninstall [--target ...] [--dry-run]
  install.sh -h|--help

With no --target, installs for `agents` always, and for `codex`/`claude` when the
agent's config directory exists or its CLI is on PATH.
EOF
}

die_usage() {
  echo "install.sh: $1" >&2
  usage >&2
  exit 2
}

# Absolute path of the directory containing this script, following symlinks.
# (readlink -f is GNU-only, so resolve by hand.)
resolve_script_dir() {
  local src dir base
  src="${BASH_SOURCE[0]}"
  while [ -h "$src" ]; do
    dir="$(cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd)"
    base="$(readlink "$src")"
    case "$base" in
      /*) src="$base" ;;
      *) src="$dir/$base" ;;
    esac
  done
  cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd
}

REPO_DIR="$(resolve_script_dir)"
SRC="$REPO_DIR/skills/codex-bot"
if [ ! -f "$SRC/SKILL.md" ]; then
  echo "install.sh: skill not found at $SRC" >&2
  exit 1
fi

CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
CLAUDE_HOME_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
AGENTS_HOME_DIR="$HOME/.agents"

START='<!-- codex-bot:start -->'
END='<!-- codex-bot:end -->'
LEGACY_START='<!-- codex-bot -->'
LEGACY_END='<!-- /codex-bot -->'

uninstall=0
no_pointer=0
force=0
dry_run=0
targets=""

add_target() {
  case "$1" in
    agents | codex | claude)
      case " $targets " in
        *" $1 "*) ;;
        *) targets="$targets $1" ;;
      esac
      ;;
    all)
      case " $targets " in
        *" agents "*) ;;
        *) targets="$targets agents" ;;
      esac
      case " $targets " in
        *" codex "*) ;;
        *) targets="$targets codex" ;;
      esac
      case " $targets " in
        *" claude "*) ;;
        *) targets="$targets claude" ;;
      esac
      ;;
    *) die_usage "unknown target: $1" ;;
  esac
}

while [ $# -gt 0 ]; do
  case "$1" in
    --target)
      [ $# -ge 2 ] || die_usage "--target needs a value"
      add_target "$2"
      shift
      ;;
    --target=*) add_target "${1#--target=}" ;;
    --uninstall) uninstall=1 ;;
    --no-pointer) no_pointer=1 ;;
    --force) force=1 ;;
    --dry-run) dry_run=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) die_usage "unknown option: $1" ;;
  esac
  shift
done

if [ -z "$targets" ]; then
  targets=" agents"
  if [ -d "$CODEX_HOME_DIR" ] || command -v codex >/dev/null 2>&1; then
    targets="$targets codex"
  fi
  if [ -d "$CLAUDE_HOME_DIR" ] || command -v claude >/dev/null 2>&1; then
    targets="$targets claude"
  fi
fi

note() {
  if [ "$dry_run" -eq 1 ]; then
    echo "dry-run: $1"
  else
    echo "$1"
  fi
}

# Per-target locations. Sets LINK and POINTER (POINTER empty for agents).
target_paths() {
  case "$1" in
    agents)
      LINK="$AGENTS_HOME_DIR/skills/codex-bot"
      POINTER=""
      ;;
    codex)
      LINK="$CODEX_HOME_DIR/skills/codex-bot"
      POINTER="$CODEX_HOME_DIR/AGENTS.md"
      ;;
    claude)
      LINK="$CLAUDE_HOME_DIR/skills/codex-bot"
      POINTER="$CLAUDE_HOME_DIR/CLAUDE.md"
      ;;
  esac
}

pointer_block() {
  cat <<EOF
$START
## Working style
For every task that changes code, config, or infrastructure, follow the \`codex-bot\` skill
($1/SKILL.md): understand first, choose simple reversible designs,
verify before claiming done, confirm risky actions, and report honestly with open items.
$END
EOF
}

# Replace the managed block (new or legacy markers) or append it. Preserves the
# rest of the file byte-for-byte; writes via temp file + mv.
update_pointer() {
  local file="$1" block tmp
  block="$(pointer_block "$2")"
  if [ "$dry_run" -eq 1 ]; then
    note "update pointer block in $file"
    return 0
  fi
  if [ ! -f "$file" ]; then
    mkdir -p "$(dirname "$file")"
    printf '%s\n' "$block" >"$file"
    echo "created $file with codex-bot pointer"
    return 0
  fi
  tmp="$file.tmp.$$"
  if grep -qF "$START" "$file"; then
    awk -v block="$block" -v start="$START" -v end="$END" '
      $0 == start { print block; inside = 1; next }
      inside && $0 == end { inside = 0; next }
      !inside { print }
    ' "$file" >"$tmp"
  elif grep -qF "$LEGACY_START" "$file"; then
    awk -v block="$block" -v start="$LEGACY_START" -v end="$LEGACY_END" '
      $0 == start { print block; inside = 1; next }
      inside && $0 == end { inside = 0; next }
      !inside { print }
    ' "$file" >"$tmp"
  else
    # Append with a single blank line separator (none if the file is empty).
    if [ -s "$file" ]; then
      awk -v block="$block" '{ print } END { print ""; print block }' "$file" >"$tmp"
    else
      printf '%s\n' "$block" >"$tmp"
    fi
  fi
  mv "$tmp" "$file"
  echo "updated pointer block in $file"
}

# Remove the managed block plus the one blank line the installer added before it.
remove_pointer() {
  local file="$1" tmp
  if [ ! -f "$file" ]; then
    return 0
  fi
  if ! grep -qF "$START" "$file" && ! grep -qF "$LEGACY_START" "$file"; then
    return 0
  fi
  if [ "$dry_run" -eq 1 ]; then
    note "remove pointer block from $file"
    return 0
  fi
  tmp="$file.tmp.$$"
  awk -v start="$START" -v end="$END" -v lstart="$LEGACY_START" -v lend="$LEGACY_END" '
    {
      if ($0 == start || $0 == lstart) {
        inside = 1
        # Drop the single blank line the installer added before the block;
        # keep any non-blank previous line.
        if (have_prev && prev != "") print prev
        have_prev = 0
        next
      }
      if (inside) {
        if ($0 == end || $0 == lend) inside = 0
        next
      }
      if (have_prev) print prev
      prev = $0
      have_prev = 1
    }
    END { if (!inside && have_prev) print prev }
  ' "$file" >"$tmp"
  mv "$tmp" "$file"
  echo "removed pointer block from $file"
}

install_link() {
  local link="$1" backup
  if [ -L "$link" ]; then
    if [ "$dry_run" -eq 1 ]; then
      note "replace symlink $link -> $SRC"
    else
      ln -sfn "$SRC" "$link"
      echo "relinked $link -> $SRC"
    fi
  elif [ -e "$link" ]; then
    if [ "$force" -ne 1 ]; then
      echo "install.sh: $link exists and is not a symlink; refusing (use --force to back it up)" >&2
      return 1
    fi
    backup="$link.backup-$(date +%Y%m%d%H%M%S)"
    if [ "$dry_run" -eq 1 ]; then
      note "move $link to $backup and link $link -> $SRC"
    else
      mv "$link" "$backup"
      ln -s "$SRC" "$link"
      echo "moved existing $link to $backup"
      echo "linked $link -> $SRC"
    fi
  else
    if [ "$dry_run" -eq 1 ]; then
      note "create $link -> $SRC"
    else
      mkdir -p "$(dirname "$link")"
      ln -s "$SRC" "$link"
      echo "linked $link -> $SRC"
    fi
  fi
}

# Is LINK a symlink whose target resolves to this repo's skill dir?
link_is_ours() {
  local link="$1" dest
  [ -L "$link" ] || return 1
  dest="$(readlink "$link")"
  case "$dest" in
    /*) ;;
    *) dest="$(cd "$(dirname "$link")" && pwd)/$dest" ;;
  esac
  # Normalize . / .. without requiring the target to exist.
  if [ -d "$dest" ]; then
    [ "$(cd -P "$dest" && pwd)" = "$SRC" ]
  else
    [ "$dest" = "$SRC" ]
  fi
}

uninstall_link() {
  local link="$1"
  if [ -L "$link" ]; then
    if link_is_ours "$link"; then
      if [ "$dry_run" -eq 1 ]; then
        note "remove symlink $link"
      else
        rm "$link"
        echo "removed symlink $link"
      fi
    else
      echo "warning: $link is a symlink to something else; leaving it" >&2
    fi
  elif [ -e "$link" ]; then
    echo "warning: $link is not a symlink; leaving it" >&2
  fi
}

for target in $targets; do
  target_paths "$target"
  if [ "$uninstall" -eq 1 ]; then
    uninstall_link "$LINK"
    if [ -n "$POINTER" ]; then
      remove_pointer "$POINTER"
    fi
  else
    install_link "$LINK"
    if [ "$no_pointer" -eq 0 ] && [ -n "$POINTER" ]; then
      update_pointer "$POINTER" "$LINK"
    fi
  fi
done

if [ "$uninstall" -eq 1 ]; then
  echo "Done. Restart your agent(s) so they drop the codex-bot skill."
else
  echo "Done. Restart your agent(s) to pick up the codex-bot skill."
fi
