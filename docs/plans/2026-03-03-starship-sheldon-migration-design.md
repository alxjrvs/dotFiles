# Starship + Sheldon Migration Design

## Goal

Replace Oh My Zsh with Starship (prompt) + Sheldon (plugin manager) for faster shell startup, fewer dependencies, and a cleaner dotfiles setup. The install script must handle the full installation.

## Replacements

| OMZ Feature | Replacement |
|---|---|
| `ZSH_THEME=minimal` | Starship with minimal config |
| `plugins=(...)` framework | Sheldon plugin manager |
| `zsh-autosuggestions` | Same repo, loaded via Sheldon |
| `git` plugin | Dropped (custom aliases `gs`, `gpr` kept) |
| `macos`, `jsontools` | Dropped |
| `docker`/`npm`/`brew` completions | `zsh-completions` standalone |
| `colored-man-pages` | `LESS_TERMCAP` env vars inline |
| `colorize`, `common-aliases`, `copyfile`, `node`, `web-search` | Dropped |
| `ENABLE_CORRECTION` | `setopt CORRECT` (plain zsh) |
| `COMPLETION_WAITING_DOTS` | Dropped |
| `source $ZSH/oh-my-zsh.sh` | `eval "$(sheldon source)"` + `eval "$(starship init zsh)"` |

## New Files

### `starship.toml`
Minimal prompt: directory (truncated to 3), git branch + status, prompt character (yellow `=>`). Everything else disabled.

### `sheldon/plugins.toml`
Three plugins:
1. `zsh-autosuggestions` — fish-like suggestions
2. `zsh-syntax-highlighting` — command coloring
3. `zsh-completions` — covers docker, npm, brew completions

## Modified Files

### `Brewfile`
Add `starship` and `sheldon` brews.

### `.zshrc`
- Remove all OMZ references (`ZSH=`, `ZSH_THEME=`, `plugins=()`, `source $ZSH/oh-my-zsh.sh`, `zstyle ':omz:...'`)
- Add `eval "$(sheldon source)"`
- Add `eval "$(starship init zsh)"`
- Add `setopt CORRECT` for autocorrection
- Add `autoload -Uz compinit && compinit` for completions
- Add colored man pages via `LESS_TERMCAP` env vars
- Keep: aliases, exports, bindkey -v, fzf, zoxide, PATH, ASDF vars

### `install.sh`
- Remove Oh My Zsh install section
- Remove zsh-autosuggestions git clone section
- Add Starship/Sheldon verification (installed via Brewfile)
- Add `sheldon lock` to download plugins
- Add symlinks: `starship.toml` → `~/.config/starship.toml`, `sheldon/plugins.toml` → `~/.config/sheldon/plugins.toml`

## Symlinks

```
~/dotFiles/starship.toml         → ~/.config/starship.toml
~/dotFiles/sheldon/plugins.toml  → ~/.config/sheldon/plugins.toml
```

## What becomes unused

`~/.oh-my-zsh` directory is no longer needed. Not auto-deleted — user cleans up manually.
