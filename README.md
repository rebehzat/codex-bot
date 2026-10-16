# codex-bot

An engineering-judgment skill for coding agents. It is not tied to a project or to one agent. It teaches the agent to work like an owner: read before acting, pick simple and reversible designs, protect secrets and data, verify before saying "done", and report honestly with open items.

The skill is a single file: [`skills/codex-bot/SKILL.md`](skills/codex-bot/SKILL.md), in the standard Agent Skills format (YAML frontmatter plus Markdown).

## Supported agents

| Target   | Skill location                       | Always-on pointer          | Used by                                   |
|----------|--------------------------------------|----------------------------|-------------------------------------------|
| `agents` | `~/.agents/skills/codex-bot`         | none                       | Devin and other tools that read `~/.agents/skills` |
| `codex`  | `$CODEX_HOME/skills/codex-bot`       | `$CODEX_HOME/AGENTS.md`    | Codex CLI (`CODEX_HOME` defaults to `~/.codex`) |
| `claude` | `$CLAUDE_CONFIG_DIR/skills/codex-bot`| `$CLAUDE_CONFIG_DIR/CLAUDE.md` | Claude Code (`CLAUDE_CONFIG_DIR` defaults to `~/.claude`) |

The pointer is a short block in the agent's global instructions file. It tells the agent to apply the skill to every code or infrastructure task, not only when the skill is auto-matched. It sits between `<!-- codex-bot:start -->` and `<!-- codex-bot:end -->` markers, and the installer manages only that block.

## Install (Linux / macOS)

```sh
git clone https://github.com/rebehzat/codex-bot.git ~/.local/share/codex-bot
~/.local/share/codex-bot/install.sh
```

With no options, the installer always sets up `agents`. It also sets up `codex` and `claude` when that agent's config directory exists or its CLI is on `PATH`. Skills are symlinked, so `git pull` updates every agent at once. Restart the agent afterwards.

```sh
install.sh [--target agents|codex|claude|all]... [--no-pointer] [--force] [--dry-run]
install.sh --uninstall [--target ...] [--dry-run]
```

- `--target` can be repeated. It overrides auto-detection.
- `--no-pointer` installs the skill without editing any instructions file.
- `--force` moves an existing non-symlink skill directory to a timestamped backup instead of refusing.
- `--dry-run` prints what would change and changes nothing.
- `--uninstall` removes symlinks that point into this checkout and removes the marked pointer blocks. It leaves everything else alone.

Re-running the installer is safe. It refreshes the pointer block in place and also migrates the block format used by earlier versions.

## Update

```sh
git -C ~/.local/share/codex-bot pull
~/.local/share/codex-bot/install.sh
```

## Manual install

Copy `skills/codex-bot/` into your agent's skills directory, for example `~/.codex/skills/codex-bot/`. To make it always apply, add a line to the agent's global instructions file (`~/.codex/AGENTS.md`, `~/.claude/CLAUDE.md`, ...) telling it to follow the `codex-bot` skill on every code or infrastructure task.

## Development

```sh
shellcheck install.sh tests/*.sh
tests/install_test.sh
```

CI runs both checks on Linux and macOS, plus a validation of the skill frontmatter.

## License

MIT
