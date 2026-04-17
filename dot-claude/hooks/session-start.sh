#!/usr/bin/env bash
# SessionStart hook: quick health check for dotfiles environment.
# Spot-checks key symlinks and warns about uncommitted changes.
# Also primes the session-window cache so the statusline renders on first paint.
# Exit 0 always — informational only, never blocks.

set -uo pipefail

DOTFILES=~/dotFiles
warnings=0

# Prime ccusage-backed session-window cache in the background (~4s otherwise)
if [[ -x "$HOME/dotFiles/scripts/session-data.sh" ]]; then
  sh "$HOME/dotFiles/scripts/session-data.sh" >/dev/null 2>&1 &
  disown 2>/dev/null || true
fi

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

# Check for uncommitted changes
if git -C "$DOTFILES" status --porcelain 2>/dev/null | grep -q .; then
  echo "warning: uncommitted changes in $DOTFILES"
  ((warnings++)) || true
fi

if [[ $warnings -eq 0 ]]; then
  echo "dotfiles: all symlinks intact, working tree clean"
fi

exit 0
