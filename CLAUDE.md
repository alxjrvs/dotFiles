# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A dotfiles repository for macOS. All config files live here and are symlinked to their expected locations via `install.sh`.

## Key Commands

```bash
./install.sh          # Full idempotent setup (Homebrew, asdf, symlinks, plugins, macOS defaults)
brew bundle           # Install/update packages from Brewfile
asdf install          # Install language versions from .tool-versions
sheldon lock --update # Update zsh plugins
```

There are no build, test, or lint commands for this repo.

## Architecture

### Symlink Model

`install.sh` uses a `link()` function that creates idempotent symlinks with interactive conflict resolution. Source files in this repo map to their destinations:

| Source | Destination |
|--------|-------------|
| `.zshrc`, `.zprofile` | `~/` |
| `.gitconfig`, `.gitmessage` | `~/` |
| `.tool-versions`, `.asdfrc`, `.npmrc` | `~/` |
| `starship.toml` | `~/.config/starship.toml` |
| `sheldon/plugins.toml` | `~/.config/sheldon/plugins.toml` |
| `ghostty/config` | `~/.config/ghostty/config` |
| `nvim/init.lua` | `~/.config/nvim/init.lua` |
| `gh/config.yml` | `~/.config/gh/config.yml` |
| `dot-claude/*` | `~/.claude/*` (CLAUDE.md, settings.json, skills/, agents/, hooks/, plugins/) |

### Shell Stack

- **Sheldon** manages zsh plugins (autosuggestions, syntax-highlighting, completions)
- **Starship** renders the prompt (purple/grey powerline theme, requires Nerd Font)
- **fzf** and **zoxide** provide fuzzy finding and smart directory jumping
- **Vi mode** keybindings (`bindkey -v`)
- Transient prompt collapses previous prompts to a single `❯` character

### Claude Code Configuration (`dot-claude/`)

This directory is symlinked wholesale to `~/.claude/`. It contains:
- `CLAUDE.md` — user-level global instructions (identity, preferences, coding style)
- `settings.json` — permissions, hooks, plugins, environment variables
- `skills/` — professional skill files (postgres, react, shadcn, etc.)
- `agents/` — custom subagent definitions
- `hooks/` — event hooks (plugin update checks, shell formatting, lock file protection)

### Language Versions

Managed by **asdf** via `.tool-versions`. Default npm packages (TypeScript, Prettier, ESLint, Claude Code) auto-install with each Node version via `.default-npm-packages`.

## Important Gotchas

- **Unicode/Nerd Font glyphs**: The Write/Edit tools strip unicode characters. Use Python to write files containing special codepoints (e.g., powerline glyphs U+E0B0, U+E0B2, U+E0A0 in `starship.toml`).
- **install.sh is interactive**: The `link()` function prompts on conflicts. Don't expect unattended runs if symlink targets already exist as regular files.
- **dot-claude vs .claude**: Source of truth is `dot-claude/` in this repo. The `.claude/` directory at repo root is the symlink target for `~/.claude/` — don't confuse it with project-local Claude config.
- **Sheldon plugin order matters**: `zsh-syntax-highlighting` must be last in `sheldon/plugins.toml`.
