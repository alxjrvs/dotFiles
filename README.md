# dotFiles

macOS dotfiles for [alxjrvs](https://github.com/alxjrvs).

## Setup

```bash
./sync.sh             # Config + symlinks only (fast, idempotent)
./sync.sh --upgrade   # Also runs brew update / upgrade / cleanup (slow)
./sync.sh --help      # All flags and sections
```

`sync.sh` is idempotent — symlinks, Brewfile bundle, mise tools, macOS defaults. Safe to re-run.

## What's here

| Path | Purpose |
|------|---------|
| `.zshrc` | Thin loader — sources fragments from `~/.config/zsh/*.zsh` |
| `zsh/` | Numbered zsh fragments (exports, options, vi, plugins, completions, prompt, tools, aliases, functions) |
| `.zprofile`, `.zshenv` | Login env, including `DOTFILES_DIR` export |
| `.gitconfig`, `.gitmessage` | Git identity, commit template, signing (gpgSign overrides live in `~/.gitconfig.local`) |
| `git-hooks/pre-commit` | Global pre-commit hook (gitleaks; referenced by `core.hooksPath`) |
| `nvim/` | AstroNvim v5 config |
| `ghostty/config` | Ghostty terminal config |
| `gnar-term/gnar-term.json` | gnar-term config |
| `atuin/config.toml` | Atuin (shell history) config |
| `lazygit/config.yml` | Lazygit config (Nord theme) |
| `bat/config` | Bat config |
| `dot-claude/` | Claude Code: `CLAUDE.md`, `settings.json`, `hooks/`, `agents/`, `commands/`, `statusline-command.sh` |
| `scripts/theme.sh` | Nova color palette (Nord-derived); hex is canonical, decimals auto-derived |
| `scripts/git-data.sh` | Git-state cache feeding the prompt and statusline |
| `Brewfile` | Homebrew packages |
| `mise.toml` | Language version pinning |
| `sheldon/plugins.toml` | Zsh plugin config |
| `Makefile` | `make lint` (shellcheck) and `make fmt` (shfmt) |

## Claude Code integration

`dot-claude/` is individually symlinked into `~/.claude/`. Contents:

- `CLAUDE.md` — user-level global instructions
- `settings.json` — permissions and env
- `hooks/` — event hooks (formatting, lock-file guard, statusline data, etc.)
- `agents/` — custom subagent definitions
- `commands/` — custom slash commands
- `statusline-command.sh` — context bar + Pro/Max rate-limit windows from native `rate_limits` JSON

## Git signing

`.gitconfig` configures SSH commit/tag signing but **does not** set `gpgSign = true` directly. The actual toggle lives in machine-local `~/.gitconfig.local` (bootstrapped by `sync.sh`). This keeps fresh boxes from failing commits before SSH keys are present.

`sync.sh` also bootstraps `~/.ssh/allowed_signers` from `~/.ssh/id_ed25519.pub` so `git log --show-signature` verifies your own commits.

To disable signing on a given machine, edit `~/.gitconfig.local`.

## gitleaks pre-commit

`core.hooksPath = ~/.config/git/hooks` (set in `.gitconfig`) points every repo at `git-hooks/pre-commit`, which runs `gitleaks protect --staged`. The hook also chain-runs any repo-local `pre-commit` if present. Emergency bypass: `git commit --no-verify`.

## difftastic

Wired as a git difftool. Run with `git dft` (alias for `git difftool`) — uses [difft](https://difftastic.wilfred.me.uk/) for syntax-aware diffs.

## Notes

- `scripts/*.sh` reference `"$DOTFILES_DIR/..."` (exported from `.zshenv`); the default points to `$HOME/dotFiles`. Override via `DOTFILES_DIR=...` if your clone lives elsewhere.
- Files containing PUA powerline glyphs (`zsh/50-prompt.zsh`) use `$'\uXXXX'` escape syntax — ASCII source, evaluated at runtime. Safe to edit with the Claude Edit tool.
- `code-review-graph` MCP is installed-on-demand via `uvx code-review-graph serve` — no persistent Python install required.
