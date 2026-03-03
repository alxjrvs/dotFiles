# Starship + Sheldon Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace Oh My Zsh with Starship (prompt) + Sheldon (plugin manager) for a faster, cleaner shell setup.

**Architecture:** Starship handles the prompt via `~/.config/starship.toml`. Sheldon manages 3 standalone zsh plugins via `~/.config/sheldon/plugins.toml`. Both configs live in the dotFiles repo and get symlinked. The install script handles everything.

**Tech Stack:** Starship, Sheldon, zsh-autosuggestions, zsh-syntax-highlighting, zsh-completions

---

### Task 1: Add starship and sheldon to Brewfile

**Files:**
- Modify: `Brewfile`

**Step 1: Add brew lines**

Add after the `brew "zoxide"` line:

```
brew "sheldon"
brew "starship"
```

Alphabetical order within the brew section isn't required (the file groups by category), but these two go with the other CLI tools.

**Step 2: Commit**

```bash
git add Brewfile
git commit -m "feat: add starship and sheldon to Brewfile"
```

---

### Task 2: Create starship.toml

**Files:**
- Create: `starship.toml`

**Step 1: Create the config file**

Create `starship.toml` in the dotFiles root:

```toml
# Minimal prompt: directory + git + prompt char
# Docs: https://starship.rs/config/

format = """$directory$git_branch$git_status$character"""

# Don't add a blank line between prompts
add_newline = false

[directory]
truncation_length = 3

[git_branch]
format = "[$branch]($style) "
style = "green"

[git_status]
format = '([$all_status$ahead_behind]($style) )'
style = "red"

[character]
success_symbol = "[=>](yellow)"
error_symbol = "[=>](red)"
vimcmd_symbol = "[<=](green)"
```

The `vimcmd_symbol` supports `bindkey -v` (vi mode) — shows a different prompt char in normal mode.

**Step 2: Commit**

```bash
git add starship.toml
git commit -m "feat: add minimal starship prompt config"
```

---

### Task 3: Create sheldon/plugins.toml

**Files:**
- Create: `sheldon/plugins.toml`

**Step 1: Create the directory and config file**

Create `sheldon/plugins.toml` in the dotFiles root:

```toml
shell = "zsh"

# Fish-like autosuggestions
[plugins.zsh-autosuggestions]
github = "zsh-users/zsh-autosuggestions"

# Syntax highlighting (must be last — see zsh-syntax-highlighting README)
[plugins.zsh-syntax-highlighting]
github = "zsh-users/zsh-syntax-highlighting"

# Additional completions for docker, npm, brew, etc.
[plugins.zsh-completions]
github = "zsh-users/zsh-completions"
dir = "src"
apply = ["fpath"]
```

Notes:
- `zsh-completions` uses `apply = ["fpath"]` because it adds to `fpath` rather than sourcing a plugin file.
- `zsh-syntax-highlighting` must be listed last per its documentation.

**Step 2: Commit**

```bash
git add sheldon/plugins.toml
git commit -m "feat: add sheldon plugin config"
```

---

### Task 4: Rewrite .zshrc

**Files:**
- Modify: `.zshrc`

**Step 1: Write the new .zshrc**

Replace the entire file with:

```zsh
export EDITOR="code -w"

# Clear scrollback
printf '\n%.0s' {1..100}

# Autocorrection
setopt CORRECT

# Vi keybindings
bindkey -v

# Completions
autoload -Uz compinit && compinit

# Homebrew completions
fpath+=("$(brew --prefix)/share/zsh/site-functions")

# Sheldon plugins
eval "$(sheldon source)"

# Starship prompt
eval "$(starship init zsh)"

# fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# zoxide
eval "$(zoxide init zsh)"

# Aliases
alias c="clear"
alias q="exit"
alias gs="git status"
alias gpr='git pull --rebase'

# asdf default packages
export ASDF_GEM_DEFAULT_PACKAGES_FILE=~/dotFiles/.default-gems
export ASDF_NPM_DEFAULT_PACKAGES_FILE=~/dotFiles/.default-npm-packages

# PATH
export PATH="/opt/homebrew/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"

# Android SDK
export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/emulator
export PATH=$PATH:$ANDROID_HOME/platform-tools

# Colored man pages
export LESS_TERMCAP_mb=$'\e[1;31m'
export LESS_TERMCAP_md=$'\e[1;36m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_so=$'\e[1;44;33m'
export LESS_TERMCAP_ue=$'\e[0m'
export LESS_TERMCAP_us=$'\e[1;32m'
```

What changed:
- Removed: `export ZSH=`, `ZSH_THEME=`, `zstyle ':omz:...'`, `ENABLE_CORRECTION=`, `COMPLETION_WAITING_DOTS=`, `plugins=(...)`, `source $ZSH/oh-my-zsh.sh`, `ret_status` line
- Added: `setopt CORRECT`, `autoload -Uz compinit && compinit`, `eval "$(sheldon source)"`, `eval "$(starship init zsh)"`, `LESS_TERMCAP` vars
- Kept: all aliases, PATH exports, ASDF vars, fzf, zoxide, bindkey, EDITOR, printf scrollback

**Step 2: Commit**

```bash
git add .zshrc
git commit -m "feat: replace oh-my-zsh with starship + sheldon in .zshrc"
```

---

### Task 5: Update install.sh

**Files:**
- Modify: `install.sh`

**Step 1: Replace sections 3 and 4**

Replace the "Oh My Zsh" section (lines 64-72) and "Zsh Plugins" section (lines 74-84) with:

```bash
# ── 3. Sheldon (plugin manager) ─────────────────────────────────────
echo ""
echo "==> Sheldon"
if command -v sheldon &>/dev/null; then
  ok "Sheldon installed"
else
  fail "Sheldon not found — should have been installed by brew bundle"
fi

# ── 4. Starship (prompt) ───────────────────────────────────────────
echo ""
echo "==> Starship"
if command -v starship &>/dev/null; then
  ok "Starship installed"
else
  fail "Starship not found — should have been installed by brew bundle"
fi
```

**Step 2: Add Sheldon config symlinks and lock to section 7 (Symlinks)**

Add these lines after the existing symlinks block, before the Claude config section:

```bash
# Sheldon config
mkdir -p "$HOME/.config/sheldon"
link "$DOTFILES_DIR/sheldon/plugins.toml" "$HOME/.config/sheldon/plugins.toml" "sheldon/plugins.toml"

# Starship config
mkdir -p "$HOME/.config"
link "$DOTFILES_DIR/starship.toml"        "$HOME/.config/starship.toml"         "starship.toml"
```

**Step 3: Add sheldon lock after symlinks section**

Add a new section after Symlinks and before Claude config:

```bash
# ── 8. Sheldon plugins ─────────────────────────────────────────────
echo ""
echo "==> Sheldon plugins"
if sheldon lock --check &>/dev/null 2>&1; then
  ok "Sheldon plugins up to date"
else
  warn "Downloading Sheldon plugins..."
  sheldon lock
fi
```

Renumber subsequent sections (Claude config → 9, fzf → 10, GH → 11, Summary → 12).

**Step 4: Commit**

```bash
git add install.sh
git commit -m "feat: replace oh-my-zsh with starship + sheldon in install.sh"
```

---

### Task 6: Verify

**Step 1: Run install.sh**

```bash
./install.sh
```

Expected: Sheldon and Starship show ✓ (installed via Brewfile). Sheldon plugins download. New symlinks created.

**Step 2: Run install.sh again**

```bash
./install.sh
```

Expected: All ✓ — proves idempotency.

**Step 3: Verify shell works**

```bash
source ~/.zshrc
```

Expected: Starship prompt appears (yellow `=>`), autosuggestions work, syntax highlighting works.

**Step 4: Verify symlinks**

```bash
ls -la ~/.config/starship.toml ~/.config/sheldon/plugins.toml
```

Expected: Both point to `~/dotFiles/...`
