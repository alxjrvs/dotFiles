# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A cross-platform dotfiles repository (macOS + Linux/Raspberry Pi) managed by **chezmoi**. Config files live in `home/` with chezmoi naming conventions and are applied to `$HOME` via `chezmoi apply`.

## Key Commands

```bash
chezmoi apply           # Apply all config files to $HOME (idempotent)
chezmoi apply -v        # Apply with verbose diff output
chezmoi diff            # Preview what apply would change (dry run)
chezmoi edit ~/.zshrc   # Edit a managed file's source template in $EDITOR
chezmoi add ~/.foo      # Add a new file to chezmoi management
chezmoi managed         # List all managed files
chezmoi doctor          # Health check
sheldon lock --update   # Update zsh plugins
```

New machine bootstrap:
```bash
chezmoi init --apply https://github.com/alxjrvs/dotFiles.git
```

There are no build, test, or lint commands for this repo.

## Architecture

### Chezmoi Source Layout

The repo uses `.chezmoiroot` to point chezmoi at the `home/` subdirectory. Files use chezmoi naming conventions:

- `dot_` prefix = file starts with `.` in target (e.g., `dot_zshrc` -> `~/.zshrc`)
- `.tmpl` suffix = processed as Go template with OS conditionals
- `run_onchange_` prefix = script re-runs when content changes
- `run_once_` prefix = script runs once per machine
- `exact_` prefix on dirs = chezmoi removes files not in source

| Source (in `home/`) | Target |
|---------------------|--------|
| `dot_zshrc.tmpl`, `dot_zprofile.tmpl` | `~/` (templated for macOS/Linux) |
| `dot_gitconfig.tmpl` | `~/.gitconfig` (1Password identity, OS credential helper) |
| `dot_gitmessage`, `dot_tool-versions`, etc. | `~/` (static) |
| `dot_config/starship.toml` | `~/.config/starship.toml` |
| `dot_config/sheldon/plugins.toml` | `~/.config/sheldon/plugins.toml` |
| `dot_config/ghostty/config` | `~/.config/ghostty/config` (macOS only) |
| `dot_config/nvim/` | `~/.config/nvim` (AstroNvim v5) |
| `dot_config/gh/config.yml` | `~/.config/gh/config.yml` |
| `dot_claude/` | `~/.claude/` (CLAUDE.md, settings, skills, agents, hooks) |

### OS-Specific Behavior

Templates use `{{ .chezmoi.os }}` ("darwin" or "linux") for:
- `.zprofile` — Homebrew shellenv (macOS), Android SDK paths (macOS)
- `.zshrc` — Homebrew vs apt completions path
- `.gitconfig` — `osxkeychain` vs `store` credential helper
- `.chezmoiignore` — Ghostty config excluded on Linux

### Package Management

Packages are declared in `home/.chezmoidata/packages.yaml` and installed by `run_onchange_install-packages.sh.tmpl`:
- **macOS**: generates a Brewfile and runs `brew bundle`
- **Linux**: `apt install` + GitHub release installs for sheldon/starship/zoxide/asdf

### 1Password Integration

On `chezmoi init`, you're prompted to opt into 1Password. If enabled, git identity (name, email) is pulled from `op://Personal/Git Identity/`. Falls back to hardcoded defaults if declined or non-interactive.

### Shell Stack

- **Sheldon** manages zsh plugins (autosuggestions, syntax-highlighting, completions)
- **Starship** renders the prompt (purple/grey powerline theme, requires Nerd Font)
- **fzf** and **zoxide** provide fuzzy finding and smart directory jumping
- **Vi mode** keybindings (`bindkey -v`)
- Transient prompt collapses previous prompts to a single character

### Claude Code Configuration (`home/dot_claude/`)

Chezmoi applies this to `~/.claude/`. Contains:
- `CLAUDE.md` — user-level global instructions (identity, preferences, coding style)
- `settings.json` — permissions, hooks, plugins, environment variables
- `exact_skills/` — professional skill files (postgres, react, shadcn, etc.)
- `exact_agents/` — custom subagent definitions
- `exact_hooks/` — event hooks (plugin update checks, shell formatting, lock file protection)

### Language Versions

Managed by **asdf** via `.tool-versions`. Default npm packages (TypeScript, Prettier, ESLint, Claude Code) auto-install with each Node version via `.default-npm-packages`.

## Important Gotchas

- **Chezmoi copies, not symlinks**: Editing `~/.zshrc` directly won't update the repo. Use `chezmoi edit ~/.zshrc` or edit the source in `home/` and run `chezmoi apply`.
- **Unicode/Nerd Font glyphs**: The Write/Edit tools strip unicode characters. Use Python to write files containing special codepoints (e.g., powerline glyphs U+E0B0, U+E0B2, U+E0A0 in `starship.toml`).
- **Template shebang placement**: Run script templates must use `{{- if ... -}}` (with trailing `-`) before `#!/bin/bash` to ensure the shebang is line 1 of the rendered output.
- **Sheldon plugin order matters**: `zsh-syntax-highlighting` must be last in `sheldon/plugins.toml`.
