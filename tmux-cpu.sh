#!/bin/sh
# tmux-cpu.sh — CPU stat with conditional color, first segment on right side
# <50%: #b87050 (orange), 50-80%: #8a6f2a (yellow), >80%: #c05050 (red)

DARK="#4a4a4a"
val=$(ps -A -o %cpu 2>/dev/null | awk 'NR>1{s+=$1} END{printf "%.0f", s}')
[ -z "$val" ] && val=0

if [ "$val" -gt 80 ]; then
  COLOR="#c05050"
elif [ "$val" -gt 50 ]; then
  COLOR="#8a6f2a"
else
  COLOR="#b87050"
fi

printf "#[bg=default,fg=%s]#[bg=%s,fg=#f0f0f0] %s%% #[bg=%s,fg=%s]#[bg=%s,fg=#cccccc,bold] CPU " \
  "$COLOR" "$COLOR" "$val" "$COLOR" "$DARK" "$DARK"
