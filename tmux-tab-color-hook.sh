#!/bin/sh
_info=$(tmux display-message -p '#{window_index}|#{W:#{window_index} }' 2>/dev/null || echo "1|1 ")
ACTIVE="${_info%%|*}"
WIN_LIST=$(printf '%s' "${_info#*|}" | tr ' ' '\n' | grep -v '^$' | sort -n)
active_color() {
  case "$(( (($1-1)%15)+1 ))" in
    1) printf '#4a9070' ;;
    2) printf '#b06078' ;;
    3) printf '#b87050' ;;
    4) printf '#5f87af' ;;
    5) printf '#8b713c' ;;
    6) printf '#6e7934' ;;
    7) printf '#508137' ;;
    8) printf '#398439' ;;
    9) printf '#378181' ;;
    10) printf '#656dbd' ;;
    11) printf '#7e69bf' ;;
    12) printf '#945eba' ;;
    13) printf '#b65485' ;;
    14) printf '#b75767' ;;
    15) printf '#797934' ;;
  esac
}
inactive_color() {
  case "$(( (($1-1)%15)+1 ))" in
    1) printf '#365a4c' ;;
    2) printf '#6e4050' ;;
    3) printf '#604838' ;;
    4) printf '#3e5770' ;;
    5) printf '#70603e' ;;
    6) printf '#68703e' ;;
    7) printf '#4f703e' ;;
    8) printf '#3e703e' ;;
    9) printf '#3e7070' ;;
    10) printf '#3e4370' ;;
    11) printf '#4b3e70' ;;
    12) printf '#5c3e70' ;;
    13) printf '#703e57' ;;
    14) printf '#703e47' ;;
    15) printf '#70703e' ;;
  esac
}
right_neighbor() { printf '%s\n' "$WIN_LIST" | awk -v w="$1" '$1+0>w+0{print $1+0;exit}'; }
{
  for WIN in $WIN_LIST; do
    if [ "$WIN" -eq "$ACTIVE" ]; then
      NAME_BG=$(active_color "$WIN")
      ID_BG="#4a4a4a"
      printf 'set-window-option -t :%s @tab_name_style "bg=%s,fg=#f0f0f0,nobold"\n' "$WIN" "$NAME_BG"
    else
      NAME_BG=$(inactive_color "$WIN")
      ID_BG="#2e2e2e"
      printf 'set-window-option -t :%s @tab_name_style "bg=%s,fg=#aaaaaa,nobold"\n' "$WIN" "$NAME_BG"
    fi
    printf 'set-window-option -t :%s @tab_arrow_on "bg=%s,fg=%s"\n' "$WIN" "$NAME_BG" "$ID_BG"
    RN=$(right_neighbor "$WIN")
    if [ -z "$RN" ]; then
      printf 'set-window-option -t :%s @tab_arrow_off "bg=default,fg=%s"\n' "$WIN" "$NAME_BG"
    else
      if [ "$RN" -eq "$ACTIVE" ]; then
        NEXT_ID_BG="#4a4a4a"
      else
        NEXT_ID_BG="#2e2e2e"
      fi
      printf 'set-window-option -t :%s @tab_arrow_off "bg=%s,fg=%s"\n' "$WIN" "$NEXT_ID_BG" "$NAME_BG"
    fi
  done
} | tmux source-file -
