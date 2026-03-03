#!/bin/bash
set -e

# ── Colors & helpers ────────────────────────────────────────────────
GREEN='\033[0;32m'  YELLOW='\033[0;33m'  RED='\033[0;31m'  NC='\033[0m'
ok()   { printf "${GREEN}  ✓ %s${NC}\n" "$1"; }
warn() { printf "${YELLOW}  → %s${NC}\n" "$1"; }
fail() { printf "${RED}  ✗ %s${NC}\n" "$1"; }

DOTFILES_DIR=~/dotFiles

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

# ── 2. Brew Bundle ──────────────────────────────────────────────────
echo ""
echo "==> Brew Bundle"
if brew bundle check --file="$DOTFILES_DIR/Brewfile" &>/dev/null; then
  ok "All Brewfile dependencies satisfied"
else
  warn "Installing missing Brewfile dependencies..."
  brew bundle --file="$DOTFILES_DIR/Brewfile"
fi

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
    asdf global "$lang" "$version"
    warn "$lang global set to $version"
  fi
done < "$DOTFILES_DIR/.tool-versions"

# ── 6. Bun via asdf ────────────────────────────────────────────────
echo ""
echo "==> Bun (via asdf)"
if ! asdf plugin list 2>/dev/null | grep -q "^bun$"; then
  warn "Adding asdf plugin: bun"
  asdf plugin add bun
fi

bun_latest="$(asdf latest bun 2>/dev/null)"
if asdf list bun 2>/dev/null | grep -q "$bun_latest"; then
  ok "bun $bun_latest installed"
else
  warn "Installing bun $bun_latest..."
  asdf install bun latest
fi

current_bun="$(asdf current bun 2>/dev/null | awk '{print $2}')"
if [ "$current_bun" = "$bun_latest" ]; then
  ok "bun global set to $bun_latest"
else
  asdf global bun latest
  warn "bun global set to latest ($bun_latest)"
fi

# ── 7. Symlinks ─────────────────────────────────────────────────────
echo ""
echo "==> Symlinks"
link "$DOTFILES_DIR/.gitconfig"          "$HOME/.gitconfig"          ".gitconfig"
link "$DOTFILES_DIR/.gitmessage"         "$HOME/.gitmessage"         ".gitmessage"
link "$DOTFILES_DIR/.zshrc"              "$HOME/.zshrc"              ".zshrc"
link "$DOTFILES_DIR/.zprofile"           "$HOME/.zprofile"           ".zprofile"
link "$DOTFILES_DIR/.tool-versions"      "$HOME/.tool-versions"      ".tool-versions"
link "$DOTFILES_DIR/.default-npm-packages" "$HOME/.default-npm-packages" ".default-npm-packages"
link "$DOTFILES_DIR/.default-gems"       "$HOME/.default-gems"       ".default-gems"
link "$DOTFILES_DIR/.asdfrc"             "$HOME/.asdfrc"             ".asdfrc"

# Sheldon config
mkdir -p "$HOME/.config/sheldon"
link "$DOTFILES_DIR/sheldon/plugins.toml" "$HOME/.config/sheldon/plugins.toml" "sheldon/plugins.toml"

# Starship config
mkdir -p "$HOME/.config"
link "$DOTFILES_DIR/starship.toml"        "$HOME/.config/starship.toml"         "starship.toml"

# ── 8. Sheldon plugins ─────────────────────────────────────────────
echo ""
echo "==> Sheldon plugins"
if sheldon lock --check &>/dev/null 2>&1; then
  ok "Sheldon plugins up to date"
else
  warn "Downloading Sheldon plugins..."
  sheldon lock
fi

# ── 9. Claude config ───────────────────────────────────────────────
echo ""
echo "==> Claude config"
mkdir -p "$HOME/.claude"
link "$DOTFILES_DIR/.claude/settings.json" "$HOME/.claude/settings.json" "claude/settings.json"
link "$DOTFILES_DIR/.claude/skills"        "$HOME/.claude/skills"        "claude/skills"
link "$DOTFILES_DIR/.claude/agents"        "$HOME/.claude/agents"        "claude/agents"

# ── 10. fzf ─────────────────────────────────────────────────────────
echo ""
echo "==> fzf"
if [ -f "$HOME/.fzf.zsh" ]; then
  ok "fzf shell integration installed"
else
  warn "Installing fzf shell integration..."
  "$(brew --prefix)/opt/fzf/install" --key-bindings --completion --no-update-rc --no-bash --no-fish
fi

# ── 11. GitHub CLI auth ────────────────────────────────────────────
echo ""
echo "==> GitHub CLI"
if gh auth status &>/dev/null; then
  ok "gh authenticated"
else
  warn "Not authenticated — run: gh auth login"
fi

# ── 12. Summary ────────────────────────────────────────────────────
echo ""
echo "==> Done!"
echo "   Restart your shell or run: source ~/.zshrc"
