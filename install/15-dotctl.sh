# shellcheck shell=bash
# dotctl — hot-path utility binary (git-data + PR-status producer).
# Installed before symlinks so scripts/hooks/prompt that call `dotctl` work
# immediately after the first sync. Interim module; Phase 5 absorbs this
# into `dotctl sync` itself once `dotctl sync` exists.

if should_run dotctl; then
  echo ""
  echo "==> dotctl"

  if ! command -v cargo > /dev/null 2>&1; then
    warn "cargo not found — skipping dotctl install (mise should provide rust)"
    return 0 2> /dev/null || exit 0
  fi

  # Install to ~/.local/bin (already on PATH via .zprofile). Forces a rebuild
  # so binary tracks the source tree, even if version string didn't bump.
  if cargo install --path "$DOTFILES_DIR/dotctl" --root "$HOME/.local" --force --quiet 2> /tmp/dotctl-install.log; then
    ok "dotctl installed"
    rm -f /tmp/dotctl-install.log
  else
    warn "dotctl install failed (see /tmp/dotctl-install.log)"
  fi
fi
