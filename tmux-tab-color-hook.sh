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
    1) printf '#264a3c' ;;
    2) printf '#5e3040' ;;
    3) printf '#503828' ;;
    4) printf '#2e4760' ;;
    5) printf '#60502e' ;;
    6) printf '#58602e' ;;
    7) printf '#3f602e' ;;
    8) printf '#2e602e' ;;
    9) printf '#2e6060' ;;
    10) printf '#2e3360' ;;
    11) printf '#3b2e60' ;;
    12) printf '#4c2e60' ;;
    13) printf '#602e47' ;;
    14) printf '#602e37' ;;
    15) printf '#60602e' ;;
  esac
}
right_neighbor() { printf '%s\n' "$WIN_LIST" | awk -v w="$1" '$1+0>w+0{print $1+0;exit}'; }
{
  for WIN in $WIN_LIST; do
    if [ "$WIN" -eq "$ACTIVE" ]; then
      NAME_BG=$(active_color "$WIN")
      ID_BG="#4a4a4a"
      printf 'set-window-option -t :%s @tab_name_style "bg=%s,fg=#ffffff,bold"\n' "$WIN" "$NAME_BG"
    else
      NAME_BG=$(inactive_color "$WIN")
      ID_BG="#2e2e2e"
      printf 'set-window-option -t :%s @tab_name_style "bg=%s,fg=#ffffff,nobold"\n' "$WIN" "$NAME_BG"
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
