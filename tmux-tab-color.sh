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
    printf '#[bg=%s,fg=#8350C2]' "$NBG"
    ;;
  active-close)
    # Active right edge: > arrow with right neighbor as bg
    NBG=$(neighbor_bg "$(right_neighbor "$WIN")")
    printf '#[bg=%s,fg=#8350C2]' "$NBG"
    ;;
esac
