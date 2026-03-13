#!/bin/zsh
# Ghostty entry point — restore from resurrect backup or create fresh session.
tmux=/opt/homebrew/bin/tmux
resurrect_last="$HOME/.tmux/resurrect/last"

# Server already running — just attach
if $tmux has-session 2>/dev/null; then
  exec $tmux attach
fi

# Resurrect backup exists — create detached, restore, then attach
if [ -e "$resurrect_last" ]; then
  $tmux new-session -d -s main
  $tmux run-shell "$HOME/.tmux/plugins/tmux-resurrect/scripts/restore.sh"
  exec $tmux attach
fi

# No backup — fresh session
exec $tmux new-session -s main
