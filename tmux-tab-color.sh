#!/bin/sh
# tmux-tab-color.sh <mode> <window_index>
MODE="${1:-open}"
WIN="${2:-0}"
ACTIVE=$(tmux display-message -p '#{window_index}' 2>/dev/null || echo 1)
dist=$((WIN - ACTIVE))
[ "$dist" -lt 0 ] && dist=$((-dist))
case "$dist" in
    1) BG='#6b3faa'; FG='#c0a8e8' ;;
    2) BG='#5c3090'; FG='#b090d8' ;;
    *) BG='#4d2478'; FG='#9070c0' ;;
esac
case "$MODE" in
    open) printf '#[bg=%s,fg=%s]' "$BG" "$FG" ;;
    close)
        if [ "$WIN" -lt "$ACTIVE" ]; then
            printf '#[bg=default,fg=%s]' "$BG"
        else
            printf '#[bg=default,fg=%s]' "$BG"
        fi
        ;;
esac
