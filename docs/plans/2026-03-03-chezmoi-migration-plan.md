# Chezmoi Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Migrate dotfiles from custom install.sh + symlinks to chezmoi, enabling cross-platform support (macOS + Raspberry Pi OS).

**Architecture:** Chezmoi manages all dotfiles from `~/dotFiles/home/` (via `.chezmoiroot`). Templated files handle OS branching. Run scripts replace install.sh. 1Password provides secrets.

**Tech Stack:** chezmoi, Go templates, 1Password CLI (`op`), Homebrew (macOS), apt (Linux)

**Design doc:** `docs/plans/2026-03-03-chezmoi-migration-design.md`

---

### Task 1: Create branch and install chezmoi

**Files:**
- None (git + brew operations only)

**Step 1: Create feature branch**

```bash
cd ~/dotFiles
git checkout -b feat/chezmoi
```

**Step 2: Install chezmoi via brew**

```bash
brew install chezmoi
```
Expected: chezmoi binary available at `$(brew --prefix)/bin/chezmoi`

**Step 3: Verify chezmoi works**

```bash
chezmoi --version
```
Expected: version string like `chezmoi version v2.x.x`

**Step 4: Commit (nothing to commit yet, just verify branch)**

```bash
git branch --show-current
```
Expected: `feat/chezmoi`

---

### Task 2: Create chezmoi root and config scaffolding

**Files:**
- Create: `.chezmoiroot`
- Create: `home/.chezmoi.yaml.tmpl`
- Create: `home/.chezmoiignore`
- Create: `home/.chezmoidata/packages.yaml`

**Step 1: Create `.chezmoiroot`**

```
home
```

This tells chezmoi to look in the `home/` subdirectory for source state.

**Step 2: Create directory structure**

```bash
mkdir -p ~/dotFiles/home/.chezmoidata
```

**Step 3: Create `home/.chezmoi.yaml.tmpl`**

This is the chezmoi config template. It runs on `chezmoi init` and prompts for 1Password setup.

```
{{- $name := "alxjrvs" -}}
{{- $email := "alxjrvs@gmail.com" -}}
{{- $onepassword := false -}}

{{- if stdinIsATTY -}}
{{-   $onepassword = promptBoolOnce . "onepassword" "Use 1Password for secrets" -}}
{{- end -}}

{{- if $onepassword -}}
{{-   $name = onepasswordRead "op://Personal/Git Identity/username" -}}
{{-   $email = onepasswordRead "op://Personal/Git Identity/email" -}}
{{- end }}

sourceDir: {{ .chezmoi.sourceDir | quote }}

data:
  name: {{ $name | quote }}
  email: {{ $email | quote }}
  onepassword: {{ $onepassword }}
```

**Step 4: Create `home/.chezmoiignore`**

```
{{- if ne .chezmoi.os "darwin" }}
.config/ghostty
{{- end }}

# chezmoi run scripts should not be targets
README.md
LICENSE
docs/
```

**Step 5: Create `home/.chezmoidata/packages.yaml`**

```yaml
packages:
  darwin:
    taps:
      - supabase/tap
      - wix/brew
    brews:
      - asdf
      - bat
      - bun
      - bundletool
      - cmake
      - fd
      - flyctl
      - fzf
      - gh
      - gnutls
      - gnupg
      - jq
      - krb5
      - libsodium
      - neovim
      - overmind
      - redis
      - ripgrep
      - sheldon
      - shfmt
      - starship
      - tmux
      - unbound
      - watchman
      - zoxide
    casks:
      - 1password
      - 1password-cli
      - claude
      - devutils
      - discord
      - docker
      - font-fira-code-nerd-font
      - ghostty
      - google-chrome
      - ngrok
      - notunes
      - rectangle
      - slack
      - tuple
      - zulu@17
    brew_services:
      - unbound
      - redis
  linux:
    apt:
      - bat
      - curl
      - fd-find
      - fzf
      - gh
      - git
      - gnupg
      - jq
      - neovim
      - ripgrep
      - tmux
      - zsh
```

**Step 6: Commit scaffolding**

```bash
git add .chezmoiroot home/.chezmoi.yaml.tmpl home/.chezmoiignore home/.chezmoidata/packages.yaml
git commit -m "feat(chezmoi): add root config, ignore, and package data"
```

---

### Task 3: Move static dotfiles into chezmoi source

These files don't need templating — just rename with chezmoi conventions and move into `home/`.

**Files:**
- Move: `.gitmessage` -> `home/dot_gitmessage`
- Move: `.tool-versions` -> `home/dot_tool-versions`
- Move: `.asdfrc` -> `home/dot_asdfrc`
- Move: `.npmrc` -> `home/dot_npmrc`
- Move: `.default-npm-packages` -> `home/dot_default-npm-packages`
- Move: `.gitignore` -> `home/dot_gitignore`
- Move: `.hushlogin` -> `home/dot_hushlogin`

**Step 1: Move all static dotfiles**

```bash
cd ~/dotFiles
git mv .gitmessage home/dot_gitmessage
git mv .tool-versions home/dot_tool-versions
git mv .asdfrc home/dot_asdfrc
git mv .npmrc home/dot_npmrc
git mv .default-npm-packages home/dot_default-npm-packages
git mv .hushlogin home/dot_hushlogin
```

Note: `.gitignore` is special — it's both a git config AND a chezmoi-managed file. We need to keep a `.gitignore` at the repo root for git, and also place a copy in `home/` for chezmoi to manage the `~/.gitignore` target. Copy it rather than move it:

```bash
cp .gitignore home/dot_gitignore
```

**Step 2: Verify files moved correctly**

```bash
ls home/dot_*
```
Expected: all 7 `dot_` files listed.

**Step 3: Commit**

```bash
git add home/dot_* .gitignore
git commit -m "feat(chezmoi): move static dotfiles into home/"
```

---

### Task 4: Move config directories into chezmoi source

**Files:**
- Move: `sheldon/plugins.toml` -> `home/dot_config/sheldon/plugins.toml`
- Move: `starship.toml` -> `home/dot_config/starship.toml`
- Move: `ghostty/config` -> `home/dot_config/ghostty/config`
- Move: `nvim/` -> `home/dot_config/nvim/`
- Move: `gh/config.yml` -> `home/dot_config/gh/config.yml`

**Step 1: Create directory structure**

```bash
mkdir -p ~/dotFiles/home/dot_config/sheldon
mkdir -p ~/dotFiles/home/dot_config/ghostty
mkdir -p ~/dotFiles/home/dot_config/gh
```

**Step 2: Move config files**

```bash
cd ~/dotFiles
git mv sheldon/plugins.toml home/dot_config/sheldon/plugins.toml
rmdir sheldon
git mv starship.toml home/dot_config/starship.toml
git mv ghostty/config home/dot_config/ghostty/config
rmdir ghostty
git mv nvim home/dot_config/nvim
git mv gh/config.yml home/dot_config/gh/config.yml
rmdir gh
```

**Important:** `starship.toml` contains Nerd Font unicode glyphs (U+E0B0, U+E0B2, U+E0A0). The Write/Edit tools strip unicode. Use `git mv` only — do NOT rewrite the file content.

**Step 3: Verify structure**

```bash
find home/dot_config -type f | sort
```

Expected:
```
home/dot_config/gh/config.yml
home/dot_config/ghostty/config
home/dot_config/nvim/.luarc.json
home/dot_config/nvim/.neoconf.json
home/dot_config/nvim/.stylua.toml
home/dot_config/nvim/init.lua
home/dot_config/nvim/lazy-lock.json
home/dot_config/nvim/lua/community.lua
home/dot_config/nvim/lua/lazy_setup.lua
home/dot_config/nvim/lua/plugins/mason.lua
home/dot_config/nvim/lua/plugins/treesitter.lua
home/dot_config/nvim/lua/polish.lua
home/dot_config/nvim/selene.toml
home/dot_config/sheldon/plugins.toml
home/dot_config/starship.toml
```

**Step 4: Commit**

```bash
git add -A
git commit -m "feat(chezmoi): move config directories into home/dot_config/"
```

---

### Task 5: Move Claude Code config into chezmoi source

**Files:**
- Move: `dot-claude/CLAUDE.md` -> `home/dot_claude/CLAUDE.md`
- Move: `dot-claude/settings.json` -> `home/dot_claude/settings.json`
- Move: `dot-claude/skills/` -> `home/dot_claude/exact_skills/`
- Move: `dot-claude/agents/` -> `home/dot_claude/exact_agents/`
- Move: `dot-claude/hooks/` -> `home/dot_claude/exact_hooks/`
- Move: `dot-claude/plugins/known_marketplaces.json` -> `home/dot_claude/plugins/known_marketplaces.json`

The `exact_` prefix on skills/agents/hooks means chezmoi will remove files in `~/.claude/skills/` that aren't tracked in the source — keeping those directories clean.

**Step 1: Create directory structure**

```bash
mkdir -p ~/dotFiles/home/dot_claude/plugins
```

**Step 2: Move files**

```bash
cd ~/dotFiles
git mv dot-claude/CLAUDE.md home/dot_claude/CLAUDE.md
git mv dot-claude/settings.json home/dot_claude/settings.json
git mv dot-claude/skills home/dot_claude/exact_skills
git mv dot-claude/agents home/dot_claude/exact_agents
git mv dot-claude/hooks home/dot_claude/exact_hooks
git mv dot-claude/plugins/known_marketplaces.json home/dot_claude/plugins/known_marketplaces.json
```

**Step 3: Clean up old dot-claude directory**

```bash
# Remove any remaining files (settings.local.json is gitignored, may or may not exist)
rm -rf dot-claude
```

**Step 4: Verify**

```bash
ls home/dot_claude/
```
Expected: `CLAUDE.md  exact_agents  exact_hooks  exact_skills  plugins  settings.json`

**Step 5: Commit**

```bash
git add -A
git commit -m "feat(chezmoi): move Claude Code config into home/dot_claude/"
```

---

### Task 6: Create templated .zprofile

**Files:**
- Create: `home/dot_zprofile.tmpl`
- Delete: `.zprofile` (old location)

**Step 1: Create `home/dot_zprofile.tmpl`**

The current `.zprofile` has macOS-specific brew shellenv and Android SDK. Template it:

```
{{- if eq .chezmoi.os "darwin" -}}
eval "$(/opt/homebrew/bin/brew shellenv)"
{{ end -}}

# XDG
export XDG_CONFIG_HOME="$HOME/.config"

# PATH (login shell only - prevents duplication in subshells)
export PATH="${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$HOME/.local/bin:$PATH"

{{- if eq .chezmoi.os "darwin" }}

# Android SDK
export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/emulator
export PATH=$PATH:$ANDROID_HOME/platform-tools
{{- end }}
```

**Step 2: Remove old `.zprofile`**

```bash
git rm .zprofile
```

**Step 3: Commit**

```bash
git add home/dot_zprofile.tmpl
git commit -m "feat(chezmoi): template .zprofile with OS conditionals"
```

---

### Task 7: Create templated .zshrc

**Files:**
- Create: `home/dot_zshrc.tmpl`
- Delete: `.zshrc` (old location)

**Step 1: Create `home/dot_zshrc.tmpl`**

Only the `fpath` line and bun/iterm2 sections need conditionals. Everything else is portable.

```
export EDITOR="nvim"

# Autocorrection
setopt CORRECT

# History
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE

# Vi keybindings
bindkey -v
KEYTIMEOUT=1

{{- if eq .chezmoi.os "darwin" }}

# Homebrew completions
fpath+=("$(brew --prefix)/share/zsh/site-functions")
{{- else }}

# Linux completions
fpath+=(/usr/share/zsh/vendor-completions)
{{- end }}

# Sheldon plugins (adds zsh-completions to fpath)
eval "$(sheldon source)"

# Syntax highlighting theme (Jack Kirby CMYK)
typeset -A ZSH_HIGHLIGHT_STYLES
ZSH_HIGHLIGHT_STYLES[default]='fg=#e6edf3'
ZSH_HIGHLIGHT_STYLES[command]='fg=#4db8cc'
ZSH_HIGHLIGHT_STYLES[alias]='fg=#4db8cc'
ZSH_HIGHLIGHT_STYLES[function]='fg=#d06cb8'
ZSH_HIGHLIGHT_STYLES[builtin]='fg=#4db8cc'
ZSH_HIGHLIGHT_STYLES[reserved-word]='fg=#d06cb8'
ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=#e05050'
ZSH_HIGHLIGHT_STYLES[precommand]='fg=#d06cb8,underline'
ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=#d4b84a'
ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=#d4b84a'
ZSH_HIGHLIGHT_STYLES[dollar-quoted-argument]='fg=#d4b84a'
ZSH_HIGHLIGHT_STYLES[dollar-double-quoted-argument]='fg=#d48040'
ZSH_HIGHLIGHT_STYLES[back-double-quoted-argument]='fg=#d48040'
ZSH_HIGHLIGHT_STYLES[single-hyphen-option]='fg=#8b949e'
ZSH_HIGHLIGHT_STYLES[double-hyphen-option]='fg=#8b949e'
ZSH_HIGHLIGHT_STYLES[globbing]='fg=#d48040'
ZSH_HIGHLIGHT_STYLES[redirection]='fg=#4db8cc'
ZSH_HIGHLIGHT_STYLES[commandseparator]='fg=#4db8cc'
ZSH_HIGHLIGHT_STYLES[assign]='fg=#d4b84a'
ZSH_HIGHLIGHT_STYLES[comment]='fg=#8b949e,italic'
ZSH_HIGHLIGHT_STYLES[path]='fg=#e6edf3,underline'

# Completions (must be after fpath extensions and sheldon)
autoload -Uz compinit
if [ "$(find ~/.zcompdump -mtime +1 2>/dev/null)" ]; then
  compinit
else
  compinit -C
fi

# Starship prompt
eval "$(starship init zsh)"

# Transient prompt - collapse previous prompts to just the character
function transient-prompt-precmd {
  TRAPINT() { transient-prompt-func; return $(( 128 + $1 )) }
}
function transient-prompt-func {
  local STARSHIP_TRANSIENT
  STARSHIP_TRANSIENT="$(starship prompt --profile transient)"
  PROMPT="$STARSHIP_TRANSIENT" RPROMPT="" zle .reset-prompt
}
autoload -Uz add-zsh-hook add-zle-hook-widget
add-zsh-hook precmd transient-prompt-precmd
add-zle-hook-widget zle-line-finish transient-prompt-func

# fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# zoxide
eval "$(zoxide init zsh)"

# Aliases
alias c="clear"
alias q="exit"
alias gs="git status"
alias gp="git push"
alias gpr='git pull --rebase'
alias gco='git checkout'
alias ..="cd .."

# asdf default packages
export ASDF_NPM_DEFAULT_PACKAGES_FILE=~/.default-npm-packages

# Colored man pages (CMYK)
export LESS_TERMCAP_mb=$'\e[1;35m'
export LESS_TERMCAP_md=$'\e[1;36m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_so=$'\e[1;33;46m'
export LESS_TERMCAP_ue=$'\e[0m'
export LESS_TERMCAP_us=$'\e[1;35m'

{{- if eq .chezmoi.os "darwin" }}

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"
{{- end }}
```

**Step 2: Remove old `.zshrc`**

```bash
git rm .zshrc
```

**Step 3: Commit**

```bash
git add home/dot_zshrc.tmpl
git commit -m "feat(chezmoi): template .zshrc with OS conditionals"
```

---

### Task 8: Create templated .gitconfig

**Files:**
- Create: `home/dot_gitconfig.tmpl`
- Delete: `.gitconfig` (old location)

**Step 1: Create `home/dot_gitconfig.tmpl`**

```
[alias]
  # Show verbose output about tags, branches or remotes
  tags = tag -l
  branches = branch -a
  remotes = remote -v
  # Pretty log output
  hist = log --graph --pretty=format:'%Cred%h%Creset %s%C(yellow)%d%Creset %Cgreen(%cr)%Creset [%an]' --abbrev-commit --date=relative

[color]
  # Use colors in Git commands that are capable of colored output when outputting to the terminal
  ui = auto
[color "branch"]
  current = yellow reverse
  local = yellow
  remote = green
[color "diff"]
  meta = yellow bold
  frag = magenta bold
  old = red bold
  new = green bold
[color "status"]
  added = yellow
  changed = green
  untracked = cyan

# Use `origin` as the default remote on the `main` branch in all cases
[branch "main"]

[user]
	name = {{ .name }}
	email = {{ .email }}
[credential]
{{- if eq .chezmoi.os "darwin" }}
	helper = osxkeychain
{{- else }}
	helper = store
{{- end }}
[core]
	editor = nvim
	excludesfile = ~/.gitignore
[init]
	defaultBranch = main
[commit]
	template = ~/.gitmessage
[push]
	autoSetupRemote = true
[pull]
	rebase = true
[rerere]
	enabled = true
[diff]
	algorithm = histogram
```

**Step 2: Remove old `.gitconfig`**

```bash
git rm .gitconfig
```

**Step 3: Commit**

```bash
git add home/dot_gitconfig.tmpl
git commit -m "feat(chezmoi): template .gitconfig with 1Password identity and OS credential helper"
```

---

### Task 9: Create run scripts (package install, macOS defaults, fzf)

**Files:**
- Create: `home/run_onchange_install-packages.sh.tmpl`
- Create: `home/run_once_setup-macos-defaults.sh.tmpl`
- Create: `home/run_once_setup-fzf.sh.tmpl`

**Step 1: Create `home/run_onchange_install-packages.sh.tmpl`**

This script runs when `.chezmoidata/packages.yaml` changes. On macOS it generates a Brewfile and runs `brew bundle`. On Linux it runs `apt install` and installs tools from GitHub releases.

```bash
{{- if eq .chezmoi.os "darwin" }}
#!/bin/bash
set -euo pipefail

# packages.yaml hash: {{ include ".chezmoidata/packages.yaml" | sha256sum }}

echo "==> Updating Homebrew..."
brew update

echo "==> Installing Brewfile packages..."
brew bundle --no-lock --file=/dev/stdin <<EOF
{{ range .packages.darwin.taps -}}
tap {{ . | quote }}
{{ end -}}
{{ range .packages.darwin.brews -}}
brew {{ . | quote }}
{{ end -}}
{{ range .packages.darwin.casks -}}
cask {{ . | quote }}
{{ end -}}
EOF

{{ range .packages.darwin.brew_services -}}
brew services start {{ . }} 2>/dev/null || true
{{ end -}}

echo "==> Cleaning up..."
brew cleanup --prune=all

echo "==> Packages up to date"

{{- else if eq .chezmoi.os "linux" }}
#!/bin/bash
set -euo pipefail

# packages.yaml hash: {{ include ".chezmoidata/packages.yaml" | sha256sum }}

echo "==> Updating apt..."
sudo apt update

echo "==> Installing apt packages..."
sudo apt install -y \
{{ range .packages.linux.apt -}}
  {{ . }} \
{{ end }}
  ;

# Tools not available via apt - install from GitHub releases
ARCH=$(dpkg --print-architecture)

# Starship
if ! command -v starship &>/dev/null; then
  echo "==> Installing Starship..."
  curl -sS https://starship.rs/install.sh | sh -s -- --yes
fi

# Sheldon
if ! command -v sheldon &>/dev/null; then
  echo "==> Installing Sheldon..."
  curl --proto '=https' -fLsS https://rossmacarthur.github.io/install/crate.sh | bash -s -- --repo rossmacarthur/sheldon --to ~/.local/bin
fi

# Zoxide
if ! command -v zoxide &>/dev/null; then
  echo "==> Installing Zoxide..."
  curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
fi

# asdf
if ! command -v asdf &>/dev/null; then
  echo "==> Installing asdf..."
  git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.15.0
fi

# bun
if ! command -v bun &>/dev/null; then
  echo "==> Installing Bun..."
  curl -fsSL https://bun.sh/install | bash
fi

echo "==> Packages up to date"
{{- end }}
```

**Step 2: Create `home/run_once_setup-macos-defaults.sh.tmpl`**

```bash
{{- if eq .chezmoi.os "darwin" }}
#!/bin/bash
set -euo pipefail

echo "==> Applying macOS defaults..."

# Fast key repeat (essential for vim keybindings)
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15
# Disable press-and-hold for keys (enables key repeat everywhere)
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
# Show hidden files in Finder
defaults write com.apple.finder AppleShowAllFiles -bool true
# Show file extensions
defaults write NSGlobalDomain AppleShowAllExtensions -bool true
# Tap to click on trackpad
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true

echo "==> macOS defaults applied"
{{- end }}
```

**Step 3: Create `home/run_once_setup-fzf.sh.tmpl`**

```bash
{{- if eq .chezmoi.os "darwin" }}
#!/bin/bash
set -euo pipefail
echo "==> Setting up fzf shell integration..."
"$(brew --prefix)/opt/fzf/install" --key-bindings --completion --no-update-rc --no-bash --no-fish
echo "==> fzf integration complete"

{{- else if eq .chezmoi.os "linux" }}
#!/bin/bash
set -euo pipefail
echo "==> Setting up fzf shell integration..."
if [ -f /usr/share/doc/fzf/examples/key-bindings.zsh ]; then
  mkdir -p ~/.fzf
  cp /usr/share/doc/fzf/examples/key-bindings.zsh ~/.fzf.zsh
fi
echo "==> fzf integration complete"
{{- end }}
```

**Step 4: Commit**

```bash
git add home/run_onchange_install-packages.sh.tmpl home/run_once_setup-macos-defaults.sh.tmpl home/run_once_setup-fzf.sh.tmpl
git commit -m "feat(chezmoi): add run scripts for packages, macOS defaults, and fzf"
```

---

### Task 10: Remove old install.sh and Brewfile

**Files:**
- Delete: `install.sh`
- Delete: `Brewfile`
- Delete: `Brewfile.lock.json`

**Step 1: Remove old files**

```bash
cd ~/dotFiles
git rm install.sh
git rm Brewfile
git rm Brewfile.lock.json
```

**Step 2: Commit**

```bash
git commit -m "chore(chezmoi): remove install.sh and Brewfile (replaced by chezmoi run scripts)"
```

---

### Task 11: Configure chezmoi to use this repo and verify

**Files:**
- Modify: `~/.config/chezmoi/chezmoi.yaml` (created by chezmoi init)

**Step 1: Point chezmoi at ~/dotFiles**

```bash
chezmoi init --source ~/dotFiles
```

This tells chezmoi to use `~/dotFiles` as its source directory (and via `.chezmoiroot`, it reads from `~/dotFiles/home/`).

**Step 2: Dry run — see what chezmoi would do**

```bash
chezmoi diff
```

Review the output carefully. It should show:
- New files being created (the templated outputs)
- Existing symlinks being replaced with real files
- No unexpected deletions

**Step 3: Verify template rendering**

```bash
chezmoi cat ~/.zprofile
chezmoi cat ~/.zshrc
chezmoi cat ~/.gitconfig
```

Check that:
- macOS-specific blocks are present (since you're running on macOS)
- `.gitconfig` has your name/email (from defaults or 1Password)
- No raw Go template syntax `{{ }}` in the output

**Step 4: Do NOT apply yet — just verify. Commit any last adjustments.**

---

### Task 12: Apply chezmoi and verify everything works

**Step 1: Apply chezmoi**

```bash
chezmoi apply -v
```

The `-v` flag shows what's being changed. This will:
- Replace symlinks in `$HOME` with real files managed by chezmoi
- Run `run_onchange_install-packages.sh` (installs packages)
- Run `run_once_setup-macos-defaults.sh` (applies macOS defaults)
- Run `run_once_setup-fzf.sh` (sets up fzf)

**Step 2: Verify shell works**

Open a new terminal tab/window and confirm:
- Starship prompt renders correctly
- `sheldon source` works (plugins load)
- `fzf` keybindings work (Ctrl+R for history)
- `zoxide` works (`z` command)
- `git config user.name` returns `alxjrvs`
- `nvim` opens AstroNvim

**Step 3: Verify chezmoi workflow**

```bash
chezmoi edit ~/.zshrc   # should open the template in nvim
chezmoi diff            # should show no diff after edit without changes
chezmoi managed         # lists all managed files
```

**Step 4: If anything is broken, rollback:**

```bash
git checkout main
./install.sh
```

**Step 5: If everything works, commit any fixes and push**

```bash
cd ~/dotFiles
git add -A
git status
# Only commit if there are changes from the apply
git commit -m "chore(chezmoi): post-apply fixes" # if needed
```

---

### Task 13: Update CLAUDE.md and project documentation

**Files:**
- Modify: `CLAUDE.md` (repo root)
- Modify: `home/dot_claude/CLAUDE.md` (user-level)

**Step 1: Update repo CLAUDE.md**

Replace references to `install.sh` and the symlink model with chezmoi workflow. Update the key commands section, architecture section, and symlink model table. Key changes:

- Key Commands: `chezmoi apply` instead of `./install.sh`, `chezmoi edit` instead of editing files directly
- Architecture: describe chezmoi source layout instead of symlink model
- Remove the symlink table, replace with chezmoi naming conventions
- Update Gotchas: note that chezmoi copies files (no symlinks), and editing workflow

**Step 2: Update user-level CLAUDE.md**

In `home/dot_claude/CLAUDE.md`, update the Dotfiles section:
- Change "Managed at `~/dotFiles` with symlinks via `install.sh`" to "Managed at `~/dotFiles` with chezmoi"
- Change editing instructions to reference `chezmoi edit` / `chezmoi apply`

**Step 3: Commit**

```bash
git add CLAUDE.md home/dot_claude/CLAUDE.md
git commit -m "docs: update CLAUDE.md for chezmoi migration"
```

---

### Task 14: Final verification and cleanup

**Step 1: Run chezmoi doctor**

```bash
chezmoi doctor
```

This checks that chezmoi's configuration is healthy. All checks should pass.

**Step 2: Verify chezmoi diff is clean**

```bash
chezmoi diff
```

Expected: no output (source and target are in sync).

**Step 3: Test re-apply is idempotent**

```bash
chezmoi apply -v
```

Expected: no changes applied, no scripts re-run.

**Step 4: Clean up any leftover empty directories from the old layout**

```bash
cd ~/dotFiles
# These should already be gone from git mv, but verify
[ -d sheldon ] && rmdir sheldon
[ -d ghostty ] && rmdir ghostty
[ -d gh ] && rmdir gh
[ -d dot-claude ] && rm -rf dot-claude
```

**Step 5: Final commit if any cleanup needed**

```bash
git add -A
git status
# commit only if there are changes
git diff --cached --quiet || git commit -m "chore(chezmoi): final cleanup"
```
