# codex-bot

A general-purpose engineering-judgment skill for coding agents such as Codex CLI. It is not tied to any project. It teaches an agent to work like an owner: read before acting, pick simple and reversible designs, be careful with security and destructive actions, verify before saying "done", and report honestly with open items.

## Install (Linux / macOS)

```sh
git clone https://github.com/rebehzat/codex-bot.git ~/.local/share/codex-bot
~/.local/share/codex-bot/install.sh
```

This symlinks the skill into `~/.codex/skills/codex-bot` and `~/.agents/skills/codex-bot`, and adds a short pointer to `~/.codex/AGENTS.md` so it applies to every task. Restart Codex afterwards.

Update with `git -C ~/.local/share/codex-bot pull`. Uninstall by removing the two symlinks and the block between `<!-- codex-bot -->` markers in `~/.codex/AGENTS.md`.

## Manual install

Copy `skills/codex-bot/SKILL.md` to `~/.codex/skills/codex-bot/SKILL.md`. To make it always apply, add a line to `~/.codex/AGENTS.md` telling the agent to follow the `codex-bot` skill on every code or infrastructure task.

## License

MIT
