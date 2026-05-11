#!/usr/bin/env bash
# SessionStart hook: quick health check for dotfiles environment.
# Spot-checks key symlinks and warns about uncommitted changes.
# Exit 0 always — informational only, never blocks.

set -uo pipefail

DOTFILES=~/dotFiles
warnings=0

# Prune stale security_warnings_state files (>7 days old) — they accumulate per session UUID
find "$HOME/.claude" -maxdepth 1 -name 'security_warnings_state_*.json' -mtime +7 -delete 2>/dev/null || true

# Check key symlinks
for pair in \
  "$HOME/.zshrc:$DOTFILES/.zshrc" \
  "$HOME/.gitconfig:$DOTFILES/.gitconfig"; do

  link="${pair%%:*}"
  target="${pair##*:}"

  if [[ ! -L "$link" ]]; then
    echo "warning: $link is not a symlink (expected -> $target)"
    ((warnings++)) || true
  elif [[ "$(readlink "$link")" != "$target" ]]; then
    echo "warning: $link points to $(readlink "$link"), expected $target"
    ((warnings++)) || true
  fi
done

exit 0
