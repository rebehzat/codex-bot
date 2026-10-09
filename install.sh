#!/usr/bin/env bash
# Installs the codex-bot skill globally for Codex (and any tool reading ~/.agents/skills).
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="$repo_dir/skills/codex-bot"

for base in "$HOME/.codex/skills" "$HOME/.agents/skills"; do
  mkdir -p "$base"
  ln -sfn "$src" "$base/codex-bot"
  echo "linked $base/codex-bot -> $src"
done

# Always-on pointer so the skill applies to every task, not only when auto-matched.
agents="$HOME/.codex/AGENTS.md"
marker="<!-- codex-bot -->"
mkdir -p "$HOME/.codex"
touch "$agents"
if ! grep -qF "$marker" "$agents"; then
  cat >> "$agents" <<'EOT'

<!-- codex-bot -->
## Working style
For every task that changes code, config, or infrastructure, follow the `codex-bot` skill
(~/.codex/skills/codex-bot/SKILL.md): understand first, choose simple reversible designs,
verify before claiming done, confirm risky actions, and report honestly with open items.
<!-- /codex-bot -->
EOT
  echo "added pointer to $agents"
fi
echo "done. restart Codex to pick it up."
