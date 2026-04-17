# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A dotfiles repository for macOS. All config files live here. Most are symlinked to their expected locations via `sync.sh`; a few (like `scripts/` and `ccusage/`) are read directly from `$HOME/dotFiles/` by shell scripts that hardcode that path.

## Key Commands

```bash
./sync.sh             # Full idempotent setup (Homebrew, mise, symlinks, plugins, macOS defaults)
brew bundle           # Install/update packages from Brewfile
mise install          # Install language versions from mise.toml
sheldon lock --update # Update zsh plugins
```

There are no build, test, or lint commands for this repo.

## Architecture

### Symlink Model

`sync.sh` uses a `link()` function that creates idempotent symlinks with interactive conflict resolution. Source files in this repo map to their destinations:

| Source | Destination |
|--------|-------------|
| `.zshrc`, `.zprofile` | `~/` |
| `.gitconfig`, `.gitmessage`, `.editorconfig` | `~/` |
| `.ripgreprc`, `.fdignore` | `~/` |
| `bat/config` | `~/.config/bat/config` |
| `mise.toml` | `~/.config/mise/config.toml` |
| `sheldon/plugins.toml` | `~/.config/sheldon/plugins.toml` |
| `ghostty/config` | `~/.config/ghostty/config` |
| `nvim/` | `~/.config/nvim` (AstroNvim v5) |
| `gh/config.yml` | `~/.config/gh/config.yml` |
| `dot-claude/*` | `~/.claude/*` (CLAUDE.md, settings.json, agents/, hooks/, commands/, statusline-command.sh) |

### Read-in-place (no symlink)

Some files are consumed directly from `$HOME/dotFiles/` by scripts that hardcode that path. These must remain at that absolute location — they are not synced anywhere:

- `scripts/git-data.sh` — git state cache; sourced by `.zshrc` prompt and the Claude statusline.
- `scripts/session-data.sh` — ccusage 5-hour-window cache; sourced by the Claude statusline and warmed by `dot-claude/hooks/session-start.sh`.
- `theme.sh` — color palette sourced by `.zshrc`'s hand-rolled prompt.
- `ccusage/limits.json` — per-account token cap map (gitignored, bootstrapped from `ccusage/limits.example.json`). Read by `scripts/session-data.sh` to resolve `--token-limit` based on `~/.claude.json`'s `oauthAccount.emailAddress`.

### Shell Stack

- **Sheldon** manages zsh plugins (autosuggestions, syntax-highlighting, completions)
- **Prompt** is hand-rolled in `.zshrc` using `promptsubst` + `theme.sh` (replaces the previous Starship setup). Requires a Nerd Font for powerline glyphs.
- **fzf** and **zoxide** provide fuzzy finding and smart directory jumping
- **Vi mode** keybindings (`bindkey -v`)
- Transient prompt collapses previous prompts to a single `❯` character

### Claude Code Configuration (`dot-claude/`)

This directory is symlinked wholesale to `~/.claude/`. It contains:
- `CLAUDE.md` — user-level global instructions (identity, preferences, coding style)
- `settings.json` — permissions, hooks, environment variables
- `agents/` — custom subagent definitions
- `hooks/` — event hooks (shell formatting, lock file protection)

#### Custom Agents

| Agent | When to use |
|-------|-------------|
| **Senior Software Engineer** | Feature implementation, bug fixes, and design decisions requiring careful trade-off analysis |
| **Code Efficiency Auditor** | Post-feature audits, refactoring phases, or cleaning up accumulated tech debt |
| **Dependency Upgrader** | Researching, evaluating, and executing upgrades of dependencies, runtimes, or frameworks |
| **UI Refine** | Iterative CSS/styling/layout changes requiring precise control over spacing, colors, and positioning |

### Language Versions

Managed by **mise** via `mise.toml`. Default npm packages (TypeScript, Prettier, ESLint, Claude Code) auto-install with each Node version via the `postinstall` hook in `mise.toml`.

## Important Gotchas

- **Unicode/Nerd Font glyphs**: The Write/Edit tools strip unicode characters. Use Python to write files containing special codepoints (e.g., powerline glyphs U+E0B0, U+E0B2, U+E0A0 in prompt code).
- **sync.sh is interactive**: The `link()` function prompts on conflicts. Don't expect unattended runs if symlink targets already exist as regular files.
- **dot-claude vs .claude**: Source of truth is `dot-claude/` in this repo. The `.claude/` directory at repo root holds machine-local overrides (e.g. `settings.local.json`) that are gitignored — don't confuse it with project-local Claude config.
- **Sheldon plugin order matters**: `zsh-syntax-highlighting` must be last in `sheldon/plugins.toml`.
- **Hardcoded `$HOME/dotFiles` path**: Scripts in `scripts/`, `ccusage/`, and `theme.sh` are read via absolute path. If the repo is cloned somewhere else, those consumers break.
