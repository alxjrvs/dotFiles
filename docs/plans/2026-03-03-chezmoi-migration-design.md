# Chezmoi Migration Design

**Date:** 2026-03-03
**Status:** Approved
**Branch:** feat/chezmoi

## Goal

Migrate dotfiles from a custom `install.sh` + symlink model to chezmoi, making the repo platform-agnostic (macOS + Raspberry Pi OS / Debian ARM).

## Repository Structure

The repo stays at `~/dotFiles`. A `.chezmoiroot` file points chezmoi at the `home/` subdirectory.

```
~/dotFiles/
├── .chezmoiroot                          # contains "home"
├── home/                                  # chezmoi source state
│   ├── .chezmoi.yaml.tmpl                # config: OS detection, 1Password
│   ├── .chezmoidata/
│   │   └── packages.yaml                 # declarative package lists per OS
│   ├── .chezmoiignore                    # skip files per OS
│   │
│   ├── dot_zshrc.tmpl                    # OS-conditional (brew vs apt completions)
│   ├── dot_zprofile.tmpl                 # OS-conditional (brew shellenv, Android SDK)
│   ├── dot_gitconfig.tmpl                # OS-conditional (credential helper), 1Password identity
│   ├── dot_gitmessage                    # static
│   ├── dot_tool-versions                 # static
│   ├── dot_asdfrc                        # static
│   ├── dot_npmrc                         # static
│   ├── dot_default-npm-packages          # static
│   ├── dot_gitignore                     # static
│   ├── dot_hushlogin                     # static
│   │
│   ├── dot_config/
│   │   ├── sheldon/plugins.toml
│   │   ├── starship.toml
│   │   ├── ghostty/config                # macOS only (ignored on Linux)
│   │   ├── nvim/                         # AstroNvim config directory
│   │   └── gh/config.yml
│   │
│   ├── dot_claude/
│   │   ├── CLAUDE.md
│   │   ├── settings.json
│   │   ├── exact_skills/
│   │   ├── exact_agents/
│   │   ├── exact_hooks/
│   │   └── plugins/known_marketplaces.json
│   │
│   ├── run_onchange_install-packages.sh.tmpl
│   ├── run_once_setup-macos-defaults.sh.tmpl
│   └── run_once_setup-fzf.sh.tmpl
│
├── docs/plans/
└── CLAUDE.md
```

### Naming Conventions

- `dot_` prefix: file starts with `.` in target
- `.tmpl` suffix: processed as Go template
- `run_onchange_`: re-runs when file content changes
- `run_once_`: runs once per machine
- `exact_` prefix on dirs: chezmoi removes files in target not present in source

## Templated Files

### `.zprofile.tmpl`

- macOS: `eval "$(/opt/homebrew/bin/brew shellenv)"`, Android SDK paths
- Linux: skips brew and Android SDK
- Shared: XDG_CONFIG_HOME, asdf shims, ~/.local/bin

### `.zshrc.tmpl`

- macOS: `fpath+=("$(brew --prefix)/share/zsh/site-functions")`
- Linux: `fpath+=(/usr/share/zsh/vendor-completions)`
- Everything else is portable as-is

### `.gitconfig.tmpl`

- Identity (`name`, `email`) from chezmoi data (optionally via 1Password)
- macOS: `credential.helper = osxkeychain`
- Linux: `credential.helper = store`
- All other sections static

### `.chezmoiignore`

- Excludes `dot_config/ghostty` on Linux
- Expandable for other macOS-only configs

## Package Installation

### Data: `.chezmoidata/packages.yaml`

Declarative package lists per OS:
- `packages.darwin.brews`: Homebrew formulae
- `packages.darwin.taps`: Homebrew taps
- `packages.darwin.casks`: Homebrew casks
- `packages.linux.apt`: apt packages
- Linux-only tools without apt packages (sheldon, starship, zoxide) installed from GitHub releases

### Script: `run_onchange_install-packages.sh.tmpl`

- macOS: generates a Brewfile from YAML data, runs `brew bundle`
- Linux: runs `apt install`, then GitHub release installs for sheldon/starship/zoxide/asdf
- Triggered by content changes in packages.yaml (via hash comment)

### Script: `run_once_setup-macos-defaults.sh.tmpl`

- Guarded by `{{ if eq .chezmoi.os "darwin" }}`
- KeyRepeat, InitialKeyRepeat, ApplePressAndHoldEnabled, Finder, trackpad settings
- Runs once per machine

### Script: `run_once_setup-fzf.sh.tmpl`

- macOS: `$(brew --prefix)/opt/fzf/install`
- Linux: fzf installed via apt, shell integration via bundled install script

## 1Password Integration

### Config: `.chezmoi.yaml.tmpl`

- On `chezmoi init`, prompts whether to use 1Password
- If yes: pulls git identity from `op://Personal/Git Identity/{username,email}`
- If no: falls back to hardcoded defaults
- Stores preference in chezmoi data so subsequent `apply` runs don't re-prompt

### Scope

Managed via 1Password now:
- Git identity (name, email)
- Git signing key (if configured)

Ready to expand later:
- SSH config/keys
- API tokens (Supabase, Fly, ngrok)
- `.npmrc` auth tokens

### Dependency

- `op` CLI: `cask "1password-cli"` on macOS, GitHub release on Linux
- Chezmoi gracefully skips 1Password when `op` unavailable and user opted out

## Migration Strategy

1. Create branch `feat/chezmoi` in `~/dotFiles`
2. Install chezmoi via brew
3. Restructure repo: move files into `home/` with chezmoi naming
4. Configure chezmoi sourceDir to `~/dotFiles`
5. Verify with `chezmoi diff` (no changes applied)
6. Apply with `chezmoi apply` (replaces symlinks with managed files)
7. Remove `install.sh` (replaced by chezmoi run scripts)

### Behavioral Change

Current: symlinks (`~/.zshrc` -> `~/dotFiles/.zshrc`)
New: chezmoi copies files to target, manages them from source

Editing workflow becomes:
- `chezmoi edit ~/.zshrc` — opens source template in $EDITOR
- Edit `~/dotFiles/home/dot_zshrc.tmpl` directly + `chezmoi apply`
- `chezmoi add ~/.some-new-config` — adds new file to source

### New Machine Bootstrap

```bash
chezmoi init --apply https://github.com/alxjrvs/dotFiles.git
```

### Rollback

Branch-based: `git checkout main` + `./install.sh` restores symlinks.

## Files Removed

- `install.sh` — replaced by chezmoi run scripts
- `Brewfile` — absorbed into `.chezmoidata/packages.yaml` (Brewfile generated at runtime)

## Files Unchanged (just renamed/moved)

All static config files keep their content, just move into `home/` with chezmoi naming prefixes.
