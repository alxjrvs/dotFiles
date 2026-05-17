# shellcheck shell=bash
# Schedule background gc / commit-graph / pack-refs for the dotfiles repo.
# Idempotent: git itself tracks whether the schedule is installed.

if should_run git; then
  echo ""
  echo "==> git maintenance"
  # GIT_CONFIG_GLOBAL redirects the maintenance.repo write to ~/.gitconfig.local
  # (machine-local) so the tracked ~/.gitconfig stays portable across boxes.
  if GIT_CONFIG_GLOBAL="$HOME/.gitconfig.local" \
    git -C "$DOTFILES_DIR" maintenance start 2> /dev/null; then
    ok "git maintenance scheduled for $DOTFILES_DIR"
  else
    dim "git maintenance already scheduled or not supported"
  fi
fi # should_run git