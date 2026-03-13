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

for arg in "$@"; do
  case "$arg" in
    -f) LINK_MODE="overwrite" ;;
    -s) LINK_MODE="skip" ;;
    --only=*)
      ONLY="${arg#--only=}"
      ;;
    -h|--help)
      echo "Usage: $0 [-f] [-s] [--only=SECTION[,SECTION,...]]"
      echo ""
      echo "Options:"
      echo "  -f              Auto-overwrite conflicts (force)"
      echo "  -s              Auto-skip conflicts"
      echo "  --only=SECTION  Only run specified section(s), comma-separated"
      echo ""
      echo "Sections:"
      echo "  brew      Homebrew, Brew Bundle, Brew doctor"
      echo "  mise      mise tool versions"
      echo "  sheldon   Sheldon plugin manager + config"
      echo "  starship  Starship prompt + config"
      echo "  symlinks  All symlinks"
      echo "  claude    Claude Code + config"
      echo "  fzf       fzf shell integration"
      echo "  gh        GitHub CLI + config"
      echo "  nvim      Neovim config"
      echo "  ghostty   Ghostty config"
      echo "  git       Git config files"
      echo "  shell     Shell config (.zshrc, .zprofile)"
      echo "  health    Health checks"
      echo "  macos     macOS defaults"
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

warn "Updating Homebrew..."
brew update

warn "Upgrading formulae and casks..."
brew upgrade
brew upgrade --cask --greedy

warn "Removing outdated versions..."
brew cleanup --prune=all

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

# ── 4. Starship (prompt) ───────────────────────────────────────────
if should_run starship; then
echo ""
echo "==> Starship"
if command -v starship &>/dev/null; then
  ok "Starship installed"
else
  fail "Starship not found — should have been installed by brew bundle"
fi
fi # should_run starship

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
if should_run symlinks git shell mise sheldon starship ghostty nvim gh claude; then
echo ""
echo "==> Symlinks"
fi

# Git config
if should_run symlinks git; then
link "$DOTFILES_DIR/.gitconfig"          "$HOME/.gitconfig"          ".gitconfig"
link "$DOTFILES_DIR/.gitmessage"         "$HOME/.gitmessage"         ".gitmessage"
link "$DOTFILES_DIR/.gitignore"          "$HOME/.gitignore"          ".gitignore"
link "$DOTFILES_DIR/.editorconfig"       "$HOME/.editorconfig"       ".editorconfig"
fi

# Shell config
if should_run symlinks shell; then
link "$DOTFILES_DIR/.zshrc"              "$HOME/.zshrc"              ".zshrc"
link "$DOTFILES_DIR/.zprofile"           "$HOME/.zprofile"           ".zprofile"
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
link "$DOTFILES_DIR/.npmrc"     "$HOME/.npmrc"                    ".npmrc"
chmod 600 "$HOME/.npmrc" 2>/dev/null || true
fi
fi # Darwin

# Sheldon config
if should_run symlinks sheldon; then
mkdir -p "$HOME/.config/sheldon"
link "$DOTFILES_DIR/sheldon/plugins.toml" "$HOME/.config/sheldon/plugins.toml" "sheldon/plugins.toml"
fi

if [ "$OS" = "Darwin" ]; then
# Starship config
if should_run symlinks starship; then
mkdir -p "$HOME/.config"
link "$DOTFILES_DIR/starship.toml"        "$HOME/.config/starship.toml"         "starship.toml"
fi

# Ghostty config
if should_run symlinks ghostty; then
mkdir -p "$HOME/.config/ghostty"
link "$DOTFILES_DIR/ghostty/config"       "$HOME/.config/ghostty/config"        "ghostty/config"
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
link "$DOTFILES_DIR/dot-claude/skills"        "$HOME/.claude/skills"        "claude/skills"
link "$DOTFILES_DIR/dot-claude/agents"        "$HOME/.claude/agents"        "claude/agents"
link "$DOTFILES_DIR/dot-claude/hooks"              "$HOME/.claude/hooks"                    "claude/hooks"
link "$DOTFILES_DIR/dot-claude/statusline-command.sh" "$HOME/.claude/statusline-command.sh" "claude/statusline-command.sh"
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
  ok "Claude Code installed ($(claude --version 2>/dev/null))"
else
  warn "Claude Code not installed — will be installed by mise postinstall hook"
fi
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
