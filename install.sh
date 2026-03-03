#!/bin/bash

# ── Colors & helpers ────────────────────────────────────────────────
GREEN='\033[0;32m'  YELLOW='\033[0;33m'  RED='\033[0;31m'  NC='\033[0m'
ok()   { printf "${GREEN}  ✓ %s${NC}\n" "$1"; }
warn() { printf "${YELLOW}  → %s${NC}\n" "$1"; }
fail() { printf "${RED}  ✗ %s${NC}\n" "$1"; }

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Cancel on failure or Ctrl-C ──────────────────────────────────
set -eo pipefail
trap 'echo ""; fail "Cancelled — stopping install."; exit 1' INT TERM

# ── link() — idempotent symlink with interactive conflict resolution ─
link() {
  local src="$1" dst="$2" label="$3"

  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    ok "$label already linked"
    return
  fi

  if [ ! -e "$dst" ] && [ ! -L "$dst" ]; then
    ln -sfn "$src" "$dst"
    warn "$label linked"
    return
  fi

  # Something else exists — ask the user
  fail "$label: $dst exists but is not our symlink"
  printf "       Overwrite with symlink to %s? [o]verwrite / [s]kip: " "$src"
  read -r choice
  case "$choice" in
    o|O)
      mv "$dst" "${dst}.bak"
      ln -sfn "$src" "$dst"
      warn "$label overwritten (backup at ${dst}.bak)"
      ;;
    *)
      ok "$label skipped"
      ;;
  esac
}

# ── 1. Homebrew ─────────────────────────────────────────────────────
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
warn "Installing/upgrading Brewfile dependencies..."
brew bundle --file="$DOTFILES_DIR/Brewfile"
ok "Brewfile dependencies up to date"

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

# ── 5. asdf languages (from .tool-versions) ─────────────────────────
echo ""
echo "==> asdf languages"
warn "Updating asdf plugins..."
asdf plugin update --all &>/dev/null && ok "asdf plugins updated" || warn "asdf plugin update failed"

while IFS=' ' read -r lang version; do
  [ -z "$lang" ] && continue

  if ! asdf plugin list 2>/dev/null | grep -q "^${lang}$"; then
    warn "Adding asdf plugin: $lang"
    asdf plugin add "$lang"
  fi

  if asdf list "$lang" 2>/dev/null | grep -q "$version"; then
    ok "$lang $version installed"
  else
    warn "Installing $lang $version..."
    asdf install "$lang" "$version"
  fi

  current="$(asdf current "$lang" 2>/dev/null | awk '{print $2}')"
  if [ "$current" = "$version" ]; then
    ok "$lang global set to $version"
  else
    asdf set --home "$lang" "$version"
    warn "$lang global set to $version"
  fi
done < "$DOTFILES_DIR/.tool-versions"

# ── 6. Symlinks ─────────────────────────────────────────────────────
echo ""
echo "==> Symlinks"
link "$DOTFILES_DIR/.gitconfig"          "$HOME/.gitconfig"          ".gitconfig"
link "$DOTFILES_DIR/.gitmessage"         "$HOME/.gitmessage"         ".gitmessage"
link "$DOTFILES_DIR/.zshrc"              "$HOME/.zshrc"              ".zshrc"
link "$DOTFILES_DIR/.zprofile"           "$HOME/.zprofile"           ".zprofile"
link "$DOTFILES_DIR/.tool-versions"      "$HOME/.tool-versions"      ".tool-versions"
link "$DOTFILES_DIR/.default-npm-packages" "$HOME/.default-npm-packages" ".default-npm-packages"
link "$DOTFILES_DIR/.asdfrc"             "$HOME/.asdfrc"             ".asdfrc"
link "$DOTFILES_DIR/.gitignore"          "$HOME/.gitignore"          ".gitignore"

# Sheldon config
mkdir -p "$HOME/.config/sheldon"
link "$DOTFILES_DIR/sheldon/plugins.toml" "$HOME/.config/sheldon/plugins.toml" "sheldon/plugins.toml"

# Starship config
mkdir -p "$HOME/.config"
link "$DOTFILES_DIR/starship.toml"        "$HOME/.config/starship.toml"         "starship.toml"

# ── 7. Sheldon plugins ─────────────────────────────────────────────
echo ""
echo "==> Sheldon plugins"
warn "Updating Sheldon plugins..."
sheldon lock --update
ok "Sheldon plugins up to date"

# ── 8. Claude Code ────────────────────────────────────────────────
echo ""
echo "==> Claude Code"
if command -v claude &>/dev/null; then
  ok "Claude Code installed ($(claude --version 2>/dev/null))"
else
  warn "Installing Claude Code..."
  npm install -g @anthropic-ai/claude-code
fi

mkdir -p "$HOME/.claude"
link "$DOTFILES_DIR/dot-claude/CLAUDE.md"     "$HOME/.claude/CLAUDE.md"     "claude/CLAUDE.md"
link "$DOTFILES_DIR/dot-claude/settings.json" "$HOME/.claude/settings.json" "claude/settings.json"
link "$DOTFILES_DIR/dot-claude/skills"        "$HOME/.claude/skills"        "claude/skills"
link "$DOTFILES_DIR/dot-claude/agents"        "$HOME/.claude/agents"        "claude/agents"
link "$DOTFILES_DIR/dot-claude/hooks"         "$HOME/.claude/hooks"         "claude/hooks"

mkdir -p "$HOME/.claude/plugins"
link "$DOTFILES_DIR/dot-claude/plugins/known_marketplaces.json" "$HOME/.claude/plugins/known_marketplaces.json" "claude/plugins/known_marketplaces.json"

# ── 9. fzf ──────────────────────────────────────────────────────────
echo ""
echo "==> fzf"
warn "Installing/updating fzf shell integration..."
"$(brew --prefix)/opt/fzf/install" --key-bindings --completion --no-update-rc --no-bash --no-fish
ok "fzf shell integration up to date"

# ── 10. GitHub CLI auth ───────────────────────────────────────────
echo ""
echo "==> GitHub CLI"
if gh auth status &>/dev/null; then
  ok "gh authenticated"
else
  warn "Not authenticated — run: gh auth login"
fi

# ── 11. Health checks ─────────────────────────────────────────
echo ""
echo "==> Health checks"

# Git config
if git config user.name &>/dev/null && git config user.email &>/dev/null; then
  ok "git: user.name and user.email configured"
else
  fail "git: missing user.name or user.email — check .gitconfig"
fi

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

# ── 12. macOS defaults ──────────────────────────────────────────────
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
ok "macOS defaults applied"

# ── 13. Brew doctor ────────────────────────────────────────────────
echo ""
echo "==> Brew doctor"
if doctor_output="$(brew doctor 2>&1)"; then
  ok "brew doctor: all good"
else
  fail "brew doctor found issues — attempting fixes..."
  echo "$doctor_output"

  # Unlinked kegs
  if echo "$doctor_output" | grep -q "unlinked kegs"; then
    warn "Relinking unlinked kegs..."
    echo "$doctor_output" | sed -n '/unlinked kegs/,/^$/p' | grep '^ ' | xargs -n1 brew link --overwrite 2>/dev/null || true
  fi

  # Outdated Xcode CLI tools
  if echo "$doctor_output" | grep -q "Command Line Tools"; then
    warn "Updating Xcode Command Line Tools..."
    softwareupdate --install --all 2>/dev/null || true
  fi

  # Stale lock files
  if echo "$doctor_output" | grep -q "lock files"; then
    warn "Removing stale lock files..."
    brew cleanup --prune=all 2>/dev/null || true
  fi

  # Re-check
  echo ""
  if brew doctor 2>/dev/null; then
    ok "brew doctor: issues resolved"
  else
    warn "Some brew doctor issues remain — run 'brew doctor' for details"
  fi
fi

# ── 14. Summary ────────────────────────────────────────────────────
echo ""
echo "==> Done!"
echo "   Restart your shell or run: source ~/.zshrc"
