#!/bin/sh
# tmux-tab-color.sh <mode> <window_index>
# Modes:
#   open         -> inactive tab body colors; for right-of-active prepends ◄ from left neighbor
#   close        -> #[bg=NEXT_SHADE,fg=SHADE]►  left-of-active closing arrow; nothing for right-of-active
#   active-open  -> #[bg=LEFT_SHADE,fg=#8350C2]◄  active opening arrow (overflows into left neighbor)
#   active-close -> #[bg=RIGHT_SHADE,fg=#8350C2]►  active closing arrow (overflows into right neighbor)

MODE="${1:-open}"
WIN="${2:-0}"

# One call: get active index and sorted window index list
_info=$(tmux display-message -p '#{window_index}|#{W:#{window_index} }' 2>/dev/null || echo "1|1 ")
ACTIVE="${_info%%|*}"
WIN_LIST=$(echo "${_info#*|}" | tr ' ' '\n' | grep -v '^$' | sort -n)

dist=$((WIN - ACTIVE))
[ "$dist" -lt 0 ] && dist=$((-dist))

shade_for_dist() {
  case "$1" in
    0) printf '#8350C2' ;;
    1) printf '#6b3faa' ;;
    2) printf '#5c3090' ;;
    *) printf '#4d2478' ;;
  esac
}
text_for_dist() {
  case "$1" in
    0) printf '#ffffff' ;;
    1) printf '#c0a8e8' ;;
    2) printf '#b090d8' ;;
    *) printf '#9070c0' ;;
  esac
}

# Find immediate left/right neighbor in window list
left_neighbor() {
  echo "$WIN_LIST" | awk -v w="$1" '$1+0 < w+0 { p=$1 } END { print p+0 }'
}
right_neighbor() {
  echo "$WIN_LIST" | awk -v w="$1" '$1+0 > w+0 { print $1+0; exit }'
}
neighbor_bg() {
  local n="$1"
  if [ -z "$n" ] || [ "$n" -eq 0 ]; then
    printf 'default'
  else
    local d=$((n - ACTIVE))
    [ "$d" -lt 0 ] && d=$((-d))
    shade_for_dist "$d"
  fi
}

BG=$(shade_for_dist "$dist")
FG=$(text_for_dist "$dist")

case "$MODE" in
  open)
    if [ "$WIN" -gt "$ACTIVE" ]; then
      # Right of active: ◄ arrow overflowing from left neighbor's bg
      NBG=$(neighbor_bg "$(left_neighbor "$WIN")")
      printf '#[bg=%s,fg=%s]◄#[bg=%s,fg=%s]' "$NBG" "$BG" "$BG" "$FG"
    else
      printf '#[bg=%s,fg=%s]' "$BG" "$FG"
    fi
    ;;
  close)
    if [ "$WIN" -lt "$ACTIVE" ]; then
      # Left of active: ► arrow overflowing into right neighbor's bg
      NBG=$(neighbor_bg "$(right_neighbor "$WIN")")
      printf '#[bg=%s,fg=%s]►' "$NBG" "$BG"
    fi
    ;;
  active-open)
    # Active's left arrow overflows into the left neighbor
    NBG=$(neighbor_bg "$(left_neighbor "$WIN")")
    printf '#[bg=%s,fg=#8350C2]◄' "$NBG"
    ;;
  active-close)
    # Active's right arrow overflows into the right neighbor
    NBG=$(neighbor_bg "$(right_neighbor "$WIN")")
    printf '#[bg=%s,fg=#8350C2]►' "$NBG"
    ;;
esac
