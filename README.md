# dotFiles

macOS dotfiles for [alxjrvs](https://github.com/alxjrvs).

## Setup

```bash
./sync.sh
```

Idempotent. Installs Homebrew packages, language versions via mise, creates symlinks, applies macOS defaults. Safe to re-run.

## What's here

| Path | Purpose |
|------|---------|
| `.zshrc`, `.zprofile` | Zsh config with hand-rolled powerline prompt |
| `.gitconfig`, `.gitmessage` | Git identity and commit template |
| `nvim/` | AstroNvim v5 config |
| `ghostty/config` | Ghostty terminal config |
| `dot-claude/` | Claude Code settings, hooks, agents, and commands |
| `scripts/` | Shell helpers sourced by the prompt and Claude statusline |
| `Brewfile` | Homebrew packages |
| `mise.toml` | Language version pinning |
| `sheldon/plugins.toml` | Zsh plugin config |

## Claude Code integration

`dot-claude/` is symlinked to `~/.claude/`. It includes:

- **hooks** — shell formatting, lock file protection
- **agents** — custom subagent definitions
- **settings.json** — permissions (allow/ask/deny) and env vars
- **statusline-command.sh** — context bar plus Pro/Max 5h + 7d rate-limit windows sourced from Claude Code's native `rate_limits` JSON

## Notes

- Scripts under `scripts/` hard-code `$HOME/dotFiles` — clone there or update those paths.
- Files with powerline glyphs (prompt code, tmux config) must be edited with Python, not the Claude Edit tool, to avoid unicode stripping.
