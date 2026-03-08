#!/bin/sh
# tmux-tab-color.sh <mode> <window_index>
# Modes:
#   open         -> left-of-active: <  prefix + colors; right-of-active: colors only
#   close        -> right-of-active: > suffix; left-of-active: nothing
#   active-open  -> < arrow overflowing into left neighbor
#   active-close -> > arrow overflowing into right neighbor
#
# Design: <1 <2 <ACTIVE> 3> 4>
#   Every left-of-active tab starts with <. Active overlaps right edge of left neighbor.
#   Every right-of-active tab ends with >. Active overlaps left edge of right neighbor.

MODE="${1:-open}"
WIN="${2:-0}"

# One call: get active index and sorted window index list
_info=$(tmux display-message -p '#{window_index}|#{W:#{window_index} }' 2>/dev/null || echo "1|1 ")
ACTIVE="${_info%%|*}"
WIN_LIST=$(echo "${_info#*|}" | tr ' ' '
' | grep -v '^$' | sort -n)

dist=$((WIN - ACTIVE))
[ "$dist" -lt 0 ] && dist=$((-dist))

shade_for_dist() {
  case "$1" in
    0) printf '#c8a84b' ;;
    1) printf '#a88a30' ;;
    2) printf '#8a7028' ;;
    *) printf '#6e5820' ;;
  esac
}
text_for_dist() {
  case "$1" in
    0) printf '#1c1008' ;;
    1) printf '#f0d878' ;;
    2) printf '#c8a84b' ;;
    *) printf '#a88a30' ;;
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
    if [ "$WIN" -lt "$ACTIVE" ]; then
      # Left of active: < arrow with left neighbor as bg, then tab body colors
      NBG=$(neighbor_bg "$(left_neighbor "$WIN")")
      printf '#[bg=%s,fg=%s]#[bg=%s,fg=%s]' "$NBG" "$BG" "$BG" "$FG"
    else
      # Right of active: just set colors (active > already handles left boundary)
      printf '#[bg=%s,fg=%s]' "$BG" "$FG"
    fi
    ;;
  close)
    if [ "$WIN" -gt "$ACTIVE" ]; then
      # Right of active: > arrow with right neighbor as bg
      NBG=$(neighbor_bg "$(right_neighbor "$WIN")")
      printf '#[bg=%s,fg=%s]' "$NBG" "$BG"
    fi
    # Left of active: nothing (active < overlaps our right edge)
    ;;
  active-open)
    # Active left edge: < arrow with left neighbor as bg
    NBG=$(neighbor_bg "$(left_neighbor "$WIN")")
    printf '#[bg=%s,fg=#c8a84b]' "$NBG"
    ;;
  active-close)
    # Active right edge: > arrow with right neighbor as bg
    NBG=$(neighbor_bg "$(right_neighbor "$WIN")")
    printf '#[bg=%s,fg=#c8a84b]' "$NBG"
    ;;
esac
