# shellcheck shell=bash
# Install lefthook hooks for THIS repo (writes .git/hooks/pre-commit which
# the global gitleaks hook chain-calls — see git-hooks/pre-commit).
# Runs shellcheck + shfmt -d on staged shell files per lefthook.yml.

if should_run lefthook; then
  echo ""
  echo "==> Lefthook (this repo)"
  if command -v lefthook &> /dev/null; then
    if (cd "$DOTFILES_DIR" && lefthook install > /dev/null 2>&1); then
      ok "lefthook hooks installed in $DOTFILES_DIR/.git/hooks/"
    else
      warn "lefthook install failed — check 'lefthook install' manually"
    fi
  else
    warn "lefthook not found — should have been installed by brew bundle"
  fi
fi # should_run lefthook