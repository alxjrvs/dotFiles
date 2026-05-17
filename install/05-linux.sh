# shellcheck shell=bash
# Linux-only: apt + default shell + git credential helper bootstrap.

[ "$OS" = "Linux" ] || return 0

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