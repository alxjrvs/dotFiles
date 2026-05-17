# shellcheck shell=bash
# Sheldon plugin manager: install/check the binary.
# Plugin lock --update lives separately in 40-sheldon-plugins.sh so it runs
# after symlinks (the plugins.toml needs to be in place first).
# Darwin: installed via brew bundle (00-brew.sh); we just verify.
# Linux: install via curl since apt's sheldon is typically too old.

if should_run sheldon; then
  echo ""
  echo "==> Sheldon"
  if command -v sheldon &> /dev/null; then
    ok "Sheldon installed"
  elif [ "$OS" = "Darwin" ]; then
    fail "Sheldon not found — should have been installed by brew bundle"
  elif [ "$OS" = "Linux" ]; then
    warn "Installing Sheldon..."
    curl --proto '=https' -fLsS https://rossmacarthur.github.io/install/crate.sh |
      bash -s -- --repo rossmacarthur/sheldon --to ~/.local/bin
    ok "Sheldon installed"
  fi
fi # should_run sheldon