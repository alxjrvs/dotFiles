#!/bin/sh
# tmux-tab-color.sh <window_index>
# Outputs a tmux style block based on distance from the active window.
ACTIVE=$(tmux display-message -p '#{window_index}' 2>/dev/null || echo 1)
WIN=$1
dist=$((WIN - ACTIVE))
[ "$dist" -lt 0 ] && dist=$((-dist))
case "$dist" in
    1) printf '#[bg=#6b3faa,fg=#c0a8e8]' ;;
    2) printf '#[bg=#5c3090,fg=#b090d8]' ;;
    *) printf '#[bg=#4d2478,fg=#9070c0]' ;;
esac
