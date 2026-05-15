#!/bin/bash

# ── Colors & helpers ────────────────────────────────────────────────
GREEN='\033[0;32m'  YELLOW='\033[0;33m'  RED='\033[0;31m'  DIM='\033[2m'  NC='\033[0m'
ok()   { printf "${GREEN}  ✓ %s${NC}\n" "$1"; }
warn() { printf "${YELLOW}  → %s${NC}\n" "$1"; }
fail() { printf "${RED}  ✗ %s${NC}\n" "$1"; }
dim()  { printf "${DIM}  - %s${NC}\n" "$1"; }

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
OS="$(uname -s)"  # "Darwin" (macOS) or "Linux" (Raspberry Pi OS)
LINK_MODE=""  # "", "overwrite", or "skip"
ONLY=""       # "", or comma-separated section names
UPGRADE=0     # 1 = run brew update/upgrade/cleanup; 0 = config-only

for arg in "$@"; do
  case "$arg" in
    -f) LINK_MODE="overwrite" ;;
    -s) LINK_MODE="skip" ;;
    --upgrade|-u) UPGRADE=1 ;;
    --only=*)
      ONLY="${arg#--only=}"
      ;;
    -h|--help)
      echo "Usage: $0 [-f] [-s] [-u|--upgrade] [--only=SECTION[,SECTION,...]]"
      echo ""
      echo "Options:"
      echo "  -f              Auto-overwrite conflicts (force)"
      echo "  -s              Auto-skip conflicts"
      echo "  -u, --upgrade   Run brew update + upgrade + cleanup (slow)"
      echo "  --only=SECTION  Only run specified section(s), comma-separated"
      echo ""
      echo "Sections:"
      echo "  brew      Homebrew, Brew Bundle, Brew doctor"
      echo "  mise      mise tool versions"
      echo "  sheldon   Sheldon plugin manager + config"
          echo "  symlinks  All symlinks"
      echo "  claude    Claude Code + config"
      echo "  fzf       fzf shell integration"
      echo "  gh        GitHub CLI + config"
      echo "  nvim      Neovim config"
      echo "  ghostty   Ghostty config"
      echo "  gnar-term gnar-term config"
      echo "  bat       Bat config"
      echo "  atuin     Atuin config"
      echo "  lazygit   Lazygit config"
      echo "  zsh       Zsh fragments (~/.config/zsh/*.zsh)"
      echo "  git       Git config files"
      echo "  shell     Shell config (.zshrc, .zprofile)"
      echo "  ssh       ~/.ssh/config symlink"
      echo "  health    Health checks"
      echo "  macos     macOS defaults + Caps→Esc LaunchAgent"
      echo "  linux     Linux system setup"
      exit 0
      ;;
    *)
      fail "Unknown option: $arg"
      echo "Usage: $0 [-f] [-s] [--only=SECTION]"
      echo "Run $0 --help for available sections."
      exit 1
      ;;
  esac
done

# ── should_run — check if a section should execute ─────────────────
# With no --only flag, everything runs. With --only, a section runs if
# any of its tags appear in the comma-separated ONLY list.
# Usage: should_run tag1 [tag2 ...]
should_run() {
  [ -z "$ONLY" ] && return 0
  local tag
  for tag in "$@"; do
    echo ",$ONLY," | grep -q ",$tag," && return 0
  done
  return 1
}

# ── Cancel on failure or Ctrl-C ──────────────────────────────────
set -eo pipefail

# ── Prevent concurrent runs ────────────────────────────────────
LOCK_FILE="/tmp/dotfiles-sync.lock"
if [ -f "$LOCK_FILE" ]; then
  lock_pid=$(cat "$LOCK_FILE" 2>/dev/null)
  if kill -0 "$lock_pid" 2>/dev/null; then
    fail "Another sync is running (pid $lock_pid)"
    exit 1
  else
    warn "Removing stale lock file"
    rm -f "$LOCK_FILE"
  fi
fi
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT
trap 'echo ""; fail "Cancelled — stopping install."; exit 1' INT TERM

# ── link() — idempotent symlink with interactive conflict resolution ─
link() {
  local src="$1" dst="$2" label="$3"

  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    dim "$label already linked"
    return
  fi

  if [ ! -e "$dst" ] && [ ! -L "$dst" ]; then
    ln -sfn "$src" "$dst"
    warn "$label linked"
    return
  fi

  # Something else exists — resolve conflict
  fail "$label: $dst exists but is not our symlink"
  local choice="$LINK_MODE"
  if [ -z "$choice" ]; then
    printf "       Overwrite with symlink to %s? [o]verwrite / [s]kip: " "$src"
    read -r choice
  fi
  case "$choice" in
    o|O|overwrite)
      mv "$dst" "${dst}.bak"
      ln -sfn "$src" "$dst"
      warn "$label overwritten (backup at ${dst}.bak)"
      ;;
    *)
      ok "$label skipped"
      ;;
  esac
}

if [ "$OS" = "Darwin" ]; then

# ── 1. Homebrew ─────────────────────────────────────────────────────
if should_run brew; then
echo ""
echo "==> Homebrew"
if command -v brew &>/dev/null; then
  ok "Homebrew installed"
else
  warn "Installing Homebrew..."
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

if (( UPGRADE )); then
  warn "Updating Homebrew..."
  brew update

  warn "Upgrading formulae and casks..."
  brew upgrade
  brew upgrade --cask

  warn "Removing outdated versions..."
  brew cleanup --prune=all
else
  dim "Skipping brew update/upgrade/cleanup (pass --upgrade to run)"
fi

# ── 2. Brew Bundle ──────────────────────────────────────────────────
echo ""
echo "==> Brew Bundle"

# Check for Xcode Command Line Tools (required by Homebrew)
if ! xcode-select --version &>/dev/null 2>&1; then
  warn "Installing Xcode Command Line Tools..."
  xcode-select --install
  fail "Xcode CLT installer opened — approve the dialog, then re-run sync.sh"
  exit 1
fi

warn "Installing Brewfile dependencies (skipping upgrades)..."
brew bundle --file="$DOTFILES_DIR/Brewfile" --no-upgrade
ok "Brewfile dependencies up to date"

# Docker Desktop provides its own docker CLI — remove the formula if both exist
if brew list --cask docker-desktop &>/dev/null && brew list --formula docker &>/dev/null; then
  warn "Removing docker formula (conflicts with Docker Desktop)..."
  brew uninstall --formula docker
  brew uninstall --formula docker-completion 2>/dev/null || true
  ok "docker formula removed — Docker Desktop provides the CLI"
fi

# ── 2a. Tier 3 fallback installs ─────────────────────────────────────
# Apple Silicon Tahoe (and other Tier 3 configurations) lack pre-built
# bottles for several formulas the Brewfile lists. Use cargo for rust
# crates and direct GitHub releases for carapace until upstream bottles
# arrive. Idempotent — re-runs are no-ops once binaries exist.
echo ""
echo "==> Tier 3 fallback installs"

if command -v cargo &>/dev/null; then
  # Each entry is crate:binary-name (binary differs for watchexec-cli, bottom).
  for entry in watchexec-cli:watchexec pueue:pueue bottom:btm; do
    crate="${entry%%:*}"
    bin="${entry##*:}"
    if command -v "$bin" &>/dev/null; then
      dim "$bin already installed"
    else
      warn "cargo install $crate (no Tahoe bottle — compiling)..."
      if cargo install "$crate"; then
        ok "$crate installed"
      else
        warn "$crate install failed"
      fi
    fi
  done
else
  warn "cargo not found — skipping rust fallbacks (run: mise install)"
fi

# Carapace: Go binary, also no Tahoe bottle. Pull the latest release from
# carapace-sh/carapace-bin. Needs jq (in Brewfile).
if command -v carapace &>/dev/null; then
  dim "carapace already installed ($(carapace --version 2>&1 | head -1))"
elif command -v jq &>/dev/null; then
  case "$(uname -m)" in
    arm64) _carapace_arch="darwin_arm64" ;;
    x86_64) _carapace_arch="darwin_amd64" ;;
    *) _carapace_arch="" ;;
  esac
  if [ -n "$_carapace_arch" ]; then
    warn "Installing carapace from GitHub releases..."
    mkdir -p "$HOME/.local/bin"
    _tmp=$(mktemp -d)
    _url=$(curl -fsSL "https://api.github.com/repos/carapace-sh/carapace-bin/releases/latest" \
      | jq -r --arg pat "$_carapace_arch" '.assets[] | select(.name | test($pat) and test("tar.gz$")) | .browser_download_url' \
      | head -1)
    if [ -n "$_url" ] \
       && curl -fsSL "$_url" -o "$_tmp/carapace.tar.gz" \
       && tar xzf "$_tmp/carapace.tar.gz" -C "$_tmp" \
       && mv "$_tmp/carapace" "$HOME/.local/bin/carapace" \
       && chmod +x "$HOME/.local/bin/carapace"; then
      ok "carapace installed at ~/.local/bin/carapace"
    else
      warn "carapace install failed"
    fi
    rm -rf "$_tmp"
  else
    warn "carapace skipped (unsupported arch: $(uname -m))"
  fi
else
  warn "carapace skipped (jq not installed)"
fi
fi # should_run brew

# ── 3. Sheldon (plugin manager) ─────────────────────────────────────
if should_run sheldon; then
echo ""
echo "==> Sheldon"
if command -v sheldon &>/dev/null; then
  ok "Sheldon installed"
else
  fail "Sheldon not found — should have been installed by brew bundle"
fi
fi # should_run sheldon

fi # Darwin

if [ "$OS" = "Linux" ]; then

# ── 1. System packages (apt) ────────────────────────────────────────
if should_run linux; then
echo ""
echo "==> System packages"
warn "Updating apt and installing packages..."
sudo apt update -y
sudo apt install -y zsh neovim git curl
ok "System packages installed"

# ── Default shell ────────────────────────────────────────────────
echo ""
echo "==> Default shell"
if [ "$(basename "$SHELL")" = "zsh" ]; then
  ok "zsh is already the default shell"
else
  warn "Setting zsh as default shell..."
  sudo chsh -s "$(which zsh)" "$USER"
  warn "zsh set as default (takes effect on next login)"
fi

# ── Git credential helper ────────────────────────────────────────
if [ ! -f "$HOME/.gitconfig.local" ]; then
  printf '[credential]\n\thelper = cache\n' > "$HOME/.gitconfig.local"
  ok "Created ~/.gitconfig.local with credential helper = cache"
else
  # shellcheck disable=SC2088 # display string, not path
  ok "~/.gitconfig.local already exists"
fi
fi # should_run linux

# ── 2. Sheldon (plugin manager) ─────────────────────────────────────
if should_run sheldon; then
echo ""
echo "==> Sheldon"
if command -v sheldon &>/dev/null; then
  ok "Sheldon installed"
else
  warn "Installing Sheldon..."
  curl --proto '=https' -fLsS https://rossmacarthur.github.io/install/crate.sh \
    | bash -s -- --repo rossmacarthur/sheldon --to ~/.local/bin
  ok "Sheldon installed"
fi
fi # should_run sheldon

fi # Linux

if [ "$OS" = "Darwin" ]; then

# ── 5. mise tools (from mise.toml) ──────────────────────────────────
if should_run mise; then
echo ""
echo "==> mise tools"
warn "Installing/updating tools from mise.toml..."
mise trust ~/.config/mise/config.toml 2>/dev/null || true
mise install
ok "mise tools up to date"
fi # should_run mise

fi # Darwin

# ── 6. Symlinks ─────────────────────────────────────────────────────
if should_run symlinks git shell mise sheldon ghostty bat gnar-term atuin lazygit zsh git-hooks nvim gh claude ssh; then
echo ""
echo "==> Symlinks"
fi

# Git config
if should_run symlinks git; then
link "$DOTFILES_DIR/.gitconfig"          "$HOME/.gitconfig"          ".gitconfig"
link "$DOTFILES_DIR/.gitmessage"         "$HOME/.gitmessage"         ".gitmessage"
link "$DOTFILES_DIR/.gitignore"          "$HOME/.gitignore"          ".gitignore"
link "$DOTFILES_DIR/.editorconfig"       "$HOME/.editorconfig"       ".editorconfig"
link "$DOTFILES_DIR/.ripgreprc"          "$HOME/.ripgreprc"          ".ripgreprc"
link "$DOTFILES_DIR/.fdignore"           "$HOME/.fdignore"           ".fdignore"

# Global git pre-commit hook (referenced by core.hooksPath in .gitconfig)
mkdir -p "$HOME/.config/git/hooks"
link "$DOTFILES_DIR/git-hooks/pre-commit" "$HOME/.config/git/hooks/pre-commit" "git-hooks/pre-commit"

# Bootstrap ~/.gitconfig.local with gpgSign overrides (only if missing).
# gpgSign was moved out of dotfiles so fresh boxes don't fail commits before
# SSH keys are present. Edit ~/.gitconfig.local to toggle signing locally.
if [ ! -f "$HOME/.gitconfig.local" ]; then
  cat >"$HOME/.gitconfig.local" <<'GITLOCAL'
# Machine-local git overrides — NOT in dotfiles.
# Enable SSH commit/tag signing on this machine.
[commit]
	gpgSign = true
[tag]
	gpgSign = true
GITLOCAL
  warn ".gitconfig.local bootstrapped (gpgSign enabled)"
else
  dim ".gitconfig.local already exists"
fi

# Bootstrap ~/.ssh/allowed_signers (required for `git log --show-signature` to
# verify your own commits). Generated from ~/.ssh/id_ed25519.pub.
_email=$(git config --file "$DOTFILES_DIR/.gitconfig" user.email 2>/dev/null)
if [ ! -f "$HOME/.ssh/allowed_signers" ] && [ -f "$HOME/.ssh/id_ed25519.pub" ] && [ -n "$_email" ]; then
  mkdir -p "$HOME/.ssh"
  printf '%s %s\n' "$_email" "$(cat "$HOME/.ssh/id_ed25519.pub")" >"$HOME/.ssh/allowed_signers"
  chmod 600 "$HOME/.ssh/allowed_signers"
  # shellcheck disable=SC2088 # display string, not path
  warn "~/.ssh/allowed_signers bootstrapped"
fi
fi

# SSH config
if should_run symlinks ssh; then
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
link "$DOTFILES_DIR/ssh/config" "$HOME/.ssh/config" "ssh/config"
chmod 600 "$HOME/.ssh/config" 2>/dev/null || true
fi

# Shell config
if should_run symlinks shell; then
link "$DOTFILES_DIR/.zshrc"              "$HOME/.zshrc"              ".zshrc"
link "$DOTFILES_DIR/.zprofile"           "$HOME/.zprofile"           ".zprofile"
link "$DOTFILES_DIR/.zshenv"             "$HOME/.zshenv"             ".zshenv"
link "$DOTFILES_DIR/.hushlogin"          "$HOME/.hushlogin"          ".hushlogin"
# Secrets file — gitignored, bootstrapped from .secrets.example
if [ ! -f "$DOTFILES_DIR/.secrets" ]; then
  echo ""
  echo "  Setting up .secrets from .secrets.example..."
  cp "$DOTFILES_DIR/.secrets.example" "$DOTFILES_DIR/.secrets"
  while IFS= read -r line; do
    if [[ "$line" =~ ^export\ ([A-Z_]+)=\"\"$ ]]; then
      var="${BASH_REMATCH[1]}"
      printf "  %s (press Enter to skip): " "$var"
      read -r value </dev/tty
      if [ -n "$value" ]; then
        sed -i '' "s|export ${var}=\"\"|export ${var}=\"${value}\"|" "$DOTFILES_DIR/.secrets"
      fi
    fi
  done <"$DOTFILES_DIR/.secrets.example"
  chmod 600 "$DOTFILES_DIR/.secrets"
fi
link "$DOTFILES_DIR/.secrets" "$HOME/.secrets" ".secrets"
fi

# mise config (Darwin only)
if [ "$OS" = "Darwin" ]; then
if should_run symlinks mise; then
mkdir -p "$HOME/.config/mise"
link "$DOTFILES_DIR/mise.toml"  "$HOME/.config/mise/config.toml"  "mise/config.toml"
fi
fi # Darwin

# Sheldon config
if should_run symlinks sheldon; then
mkdir -p "$HOME/.config/sheldon"
link "$DOTFILES_DIR/sheldon/plugins.toml" "$HOME/.config/sheldon/plugins.toml" "sheldon/plugins.toml"
fi

if [ "$OS" = "Darwin" ]; then
# Ghostty config
if should_run symlinks ghostty; then
mkdir -p "$HOME/.config/ghostty"
link "$DOTFILES_DIR/ghostty/config"       "$HOME/.config/ghostty/config"        "ghostty/config"
fi

# Bat config
if should_run symlinks bat; then
mkdir -p "$HOME/.config/bat"
link "$DOTFILES_DIR/bat/config"           "$HOME/.config/bat/config"            "bat/config"
fi

# gnar-term config
if should_run symlinks gnar-term; then
mkdir -p "$HOME/.config/gnar-term"
link "$DOTFILES_DIR/gnar-term/gnar-term.json" "$HOME/.config/gnar-term/gnar-term.json" "gnar-term/gnar-term.json"
fi

# atuin config
if should_run symlinks atuin; then
mkdir -p "$HOME/.config/atuin"
link "$DOTFILES_DIR/atuin/config.toml" "$HOME/.config/atuin/config.toml" "atuin/config.toml"
fi

# lazygit config
if should_run symlinks lazygit; then
mkdir -p "$HOME/.config/lazygit"
link "$DOTFILES_DIR/lazygit/config.yml" "$HOME/.config/lazygit/config.yml" "lazygit/config.yml"
fi

# zsh fragments (sourced by ~/.zshrc — see zsh/README.md)
if should_run symlinks zsh; then
mkdir -p "$HOME/.config/zsh"
for _zf in "$DOTFILES_DIR"/zsh/[0-9]*.zsh; do
  [ -f "$_zf" ] || continue
  _name=$(basename "$_zf")
  link "$_zf" "$HOME/.config/zsh/$_name" "zsh/$_name"
done
fi
fi # Darwin

# Neovim config (AstroNvim — symlink entire directory)
if should_run symlinks nvim; then
# Migration: remove old single-file symlink if present
if [ -L "$HOME/.config/nvim/init.lua" ] && [ ! -L "$HOME/.config/nvim" ]; then
  warn "Removing old nvim/init.lua symlink (migrating to AstroNvim)"
  rm "$HOME/.config/nvim/init.lua"
  rmdir "$HOME/.config/nvim" 2>/dev/null || true
fi
link "$DOTFILES_DIR/nvim"                 "$HOME/.config/nvim"                  "nvim (AstroNvim)"
fi

# GitHub CLI config
if should_run symlinks gh; then
mkdir -p "$HOME/.config/gh"
link "$DOTFILES_DIR/gh/config.yml" "$HOME/.config/gh/config.yml" "gh/config.yml"
fi

# Claude Code config
if should_run symlinks claude; then
mkdir -p "$HOME/.claude"
link "$DOTFILES_DIR/dot-claude/CLAUDE.md"     "$HOME/.claude/CLAUDE.md"     "claude/CLAUDE.md"
link "$DOTFILES_DIR/dot-claude/settings.json" "$HOME/.claude/settings.json" "claude/settings.json"
link "$DOTFILES_DIR/dot-claude/hooks"              "$HOME/.claude/hooks"                    "claude/hooks"
link "$DOTFILES_DIR/dot-claude/agents"             "$HOME/.claude/agents"                   "claude/agents"
link "$DOTFILES_DIR/dot-claude/commands"           "$HOME/.claude/commands"                 "claude/commands"
link "$DOTFILES_DIR/dot-claude/statusline-command.sh" "$HOME/.claude/statusline-command.sh" "claude/statusline-command.sh"
# settings.local.json is gitignored (contains secrets) — only link if present
if [ -f "$DOTFILES_DIR/dot-claude/settings.local.json" ]; then
  link "$DOTFILES_DIR/dot-claude/settings.local.json" "$HOME/.claude/settings.local.json" "claude/settings.local.json"
else
  dim "claude/settings.local.json not present — skipping"
fi
fi

# ── 7. Sheldon plugins ─────────────────────────────────────────────
if should_run sheldon; then
echo ""
echo "==> Sheldon plugins"
warn "Updating Sheldon plugins..."
timeout 30 sheldon lock --update || warn "Sheldon lock timed out or failed (may be offline) — skipping"
ok "Sheldon plugins up to date"
fi # should_run sheldon

# ── 8. Claude Code ────────────────────────────────────────────────
if should_run claude; then
echo ""
echo "==> Claude Code"
if command -v claude &>/dev/null; then
  ok "Claude Code CLI installed ($(claude --version 2>/dev/null))"
else
  warn "Installing Claude Code CLI (native installer)..."
  if curl -fsSL https://claude.ai/install.sh | bash; then
    ok "Claude Code CLI installed"
  else
    fail "Claude Code CLI install failed — re-run sync.sh or install manually"
  fi
fi

# code-review-graph — MCP server installed/run on demand via `uvx code-review-graph`.
# No persistent install needed; configure it under user-level Claude settings if desired.

fi # should_run claude

if [ "$OS" = "Darwin" ]; then

# ── 9. fzf ──────────────────────────────────────────────────────────
if should_run fzf; then
echo ""
echo "==> fzf"
warn "Installing/updating fzf shell integration..."
"$(brew --prefix)/opt/fzf/install" --key-bindings --completion --no-update-rc --no-bash --no-fish
ok "fzf shell integration up to date"
fi # should_run fzf

fi # Darwin

# ── 10. GitHub CLI auth ───────────────────────────────────────────
if should_run gh; then
echo ""
echo "==> GitHub CLI"
if gh auth status &>/dev/null; then
  ok "gh authenticated"
  # gh-dash: TUI for PR/issue triage. Requires auth.
  if gh extension list 2>/dev/null | grep -q dlvhdr/gh-dash; then
    dim "gh-dash extension already installed"
  else
    warn "Installing gh-dash extension..."
    if gh extension install dlvhdr/gh-dash; then
      ok "gh-dash installed"
    else
      warn "gh-dash install failed"
    fi
  fi
else
  warn "Not authenticated — run: gh auth login"
fi
fi # should_run gh

# ── 12. Health checks ─────────────────────────────────────────
if should_run health; then
echo ""
echo "==> Health checks"

# Git config
if git config user.name &>/dev/null && git config user.email &>/dev/null; then
  ok "git: user.name and user.email configured"
else
  fail "git: missing user.name or user.email — check .gitconfig"
fi

if [ "$OS" = "Darwin" ]; then
# Node
if command -v node &>/dev/null; then
  ok "node: $(node --version)"
else
  fail "node: not found"
fi

# Bun
if command -v bun &>/dev/null; then
  ok "bun: $(bun --version)"
else
  fail "bun: not found"
fi
fi # Darwin
fi # should_run health

if [ "$OS" = "Darwin" ]; then

# ── 12. macOS defaults ──────────────────────────────────────────────
if should_run macos; then
echo ""
echo "==> macOS defaults"
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
# Dock settings
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock autohide-time-modifier -float 0.3
defaults write com.apple.dock tilesize -int 48
# Apply Dock and Finder changes
killall Dock 2>/dev/null || true
killall Finder 2>/dev/null || true
ok "macOS defaults applied (Dock and Finder restarted)"

# Caps Lock → Escape via hidutil. LaunchAgent re-applies at every login;
# the inline hidutil call below applies it for the current session.
mkdir -p "$HOME/Library/LaunchAgents"
link "$DOTFILES_DIR/macos/LaunchAgents/com.alxjrvs.capsescape.plist" \
     "$HOME/Library/LaunchAgents/com.alxjrvs.capsescape.plist" \
     "LaunchAgents/capsescape.plist"
if ! launchctl list 2>/dev/null | grep -q com.alxjrvs.capsescape; then
  launchctl load -w "$HOME/Library/LaunchAgents/com.alxjrvs.capsescape.plist" 2>/dev/null || true
fi
if hidutil property --set '{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x700000029}]}' >/dev/null 2>&1; then
  ok "Caps Lock → Escape remap active"
else
  warn "hidutil failed — Caps→Esc not active this session"
fi
fi # should_run macos

# ── 13. Brew doctor ────────────────────────────────────────────────
if should_run brew; then
echo ""
echo "==> Brew doctor"
if brew doctor 2>&1 | grep -q "ready to brew"; then
  ok "brew doctor: all good"
else
  warn "brew doctor found issues — run 'brew doctor' for details"
fi
fi # should_run brew

fi # Darwin

# ── 14. Summary ────────────────────────────────────────────────────
echo ""
echo "==> Done!"
if [ -z "$ONLY" ]; then
  echo "   Restart your shell or run: source ~/.zshrc"
fi
