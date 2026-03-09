#!/bin/sh
# tmux-bat.sh — Battery stat with conditional color + charging indicator
# >50%: #4a9070 (green), 20-50%: #8a6f2a (yellow), <20%: #c05050 (red)

DARK="default"
batt_info=$(pmset -g batt 2>/dev/null)
val=$(echo "$batt_info" | grep -o '[0-9]*%' | head -1 | tr -d '%')
[ -z "$val" ] && val=0

charging=""
echo "$batt_info" | grep -q "AC Power" && charging="⚡"

if [ "$val" -gt 50 ]; then
  COLOR="#4a9070"
elif [ "$val" -gt 20 ]; then
  COLOR="#8a6f2a"
else
  COLOR="#c05050"
fi

printf "#[nobold,bg=%s,fg=%s]#[bg=%s,fg=#f0f0f0] %s%s%% #[bg=%s,fg=%s]#[bg=%s,fg=#cccccc,bold] BAT #[nobold,bg=default]" \
  "$DARK" "$COLOR" "$COLOR" "$charging" "$val" "$COLOR" "$DARK" "$DARK"
