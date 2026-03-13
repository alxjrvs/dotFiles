#!/bin/sh
# tmux-powerline.sh - Unified tmux powerline layout
# Colors: Nord Lake Superior palette (theme.sh)
# Ensure Homebrew binaries (tmux, etc.) are available in run-shell context
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
# All formatting, glyphs, and colors centralized here.
# Raw data from tmux-data.sh; styling applied by this script.
# Usage: tmux-powerline.sh <command> [args...]
# Commands: status-right, dir <path>, pane-git <path>, pane-colors, tab-colors

# shellcheck source=../theme.sh
. "$HOME/dotFiles/theme.sh"

cmd_status_right() {
  TERM_BG=$NOVA_STATUS_BG
  DATA="$HOME/dotFiles/tmux-scripts/tmux-data.sh"

  _all=$("$DATA" all)
  cpu_val="${_all%%|*}"; _rest="${_all#*|}"
  bat_raw="${_rest#*|}"

  case "$bat_raw" in
    ⚡*) bat_charging="⚡"; bat_val="${bat_raw#⚡}" ;;
    *)      bat_charging="";      bat_val="$bat_raw" ;;
  esac

  # Nova palette — see theme.sh for all values
  CPU_LBL=$NOVA_CPU_NORM_DK
  if [ "$cpu_val" -gt 80 ]; then CPU_VAL=$NOVA_CPU_HIGH
  elif [ "$cpu_val" -gt 50 ]; then CPU_VAL=$NOVA_CPU_WARN
  else CPU_VAL=$NOVA_CPU_NORM
  fi
  BAT_LBL=$NOVA_BAT_NORM_DK
  if [ "$bat_val" -gt 50 ]; then BAT_VAL=$NOVA_BAT_NORM
  elif [ "$bat_val" -gt 20 ]; then BAT_VAL=$NOVA_BAT_WARN
  else BAT_VAL=$NOVA_BAT_LOW
  fi
  TIME_BG=$NOVA_TIME; TIME_DK=$NOVA_TIME_DK

  _dt=$(date '+%-l:%M %p|%a %b %-d')
  time_val="${_dt%%|*}"
  date_val=$(echo "${_dt#*|}" | tr 'a-z' 'A-Z')

  cpu_display=$(printf '%4s' "${cpu_val}%")
  bat_display=$(printf '%4s' "${bat_charging}${bat_val}%")

  SL=""
  BS=""

  o="#[bg=${CPU_VAL},fg=${TERM_BG}]${SL}"
  o="${o}#[bg=${CPU_VAL},fg=${NOVA_FG}] ${cpu_display} "
  o="${o}#[bg=${CPU_LBL},fg=${CPU_VAL}]${SL}"
  o="${o}#[bg=${CPU_LBL},fg=${NOVA_FG},nobold] CPU "

  o="${o}#[bg=${CPU_LBL},fg=${TERM_BG}]${BS}"
  o="${o}#[bg=${BAT_VAL},fg=${TERM_BG}]${SL}"
  o="${o}#[bg=${BAT_VAL},fg=${NOVA_FG}] ${bat_display} "
  o="${o}#[bg=${BAT_LBL},fg=${BAT_VAL}]${SL}"
  o="${o}#[bg=${BAT_LBL},fg=${NOVA_FG},nobold] BAT "

  o="${o}#[bg=${BAT_LBL},fg=${TERM_BG}]${BS}"
  o="${o}#[bg=${TIME_BG},fg=${TERM_BG}]${SL}"
  o="${o}#[bg=${TIME_BG},fg=${NOVA_FG}] ${time_val} "
  o="${o}#[bg=${TIME_DK},fg=${TIME_BG}]${SL}"
  o="${o}#[bg=${TIME_DK},fg=${NOVA_FG},nobold] ${date_val} "

  printf '%s' "$o"
}

cmd_dir() {
  # Returns last 2 path components (matches starship truncation_length=2)
  p=$(echo "$1" | sed "s|^$HOME|~|")
  echo "$p" | awk -F'/' '{n=NF; if(n>=2) print $(n-1)"/"$n; else print $n}'

}


cmd_tab_colors() {
  TERM_BG=$NOVA_STATUS_BG
  _info=$(tmux display-message -p '#{window_index}|#{W:#{window_index} }' 2>/dev/null || echo "1|1 ")
  ACTIVE="${_info%%|*}"
  WIN_LIST=$(printf '%s\n' "${_info#*|}" | tr ' ' '\n' | grep -v '^$' | sort -n)
  active_dark_color() {
    case "$(( (($1-1)%6)+1 ))" in
      1) printf '%s' "$NOVA_TAB_A1_DK" ;;
      2) printf '%s' "$NOVA_TAB_A2_DK" ;;
      3) printf '%s' "$NOVA_TAB_A3_DK" ;;
      4) printf '%s' "$NOVA_TAB_A4_DK" ;;
      5) printf '%s' "$NOVA_TAB_A5_DK" ;;
      6) printf '%s' "$NOVA_TAB_A6_DK" ;;
    esac
  }
  # Active tab ID section: fixed blue (all active tabs use same ID color)
  active_name_color() { printf '%s' "$NOVA_TAB_ACTIVE_ID"; }
  right_neighbor() { printf '%s\n' "$WIN_LIST" | awk -v w="$1" '$1+0>w+0{print $1+0;exit}'; }
  {
    for WIN in $WIN_LIST; do
      # Show name segment only for explicitly named windows (automatic-rename=off)
      _auto=$(tmux display-message -t :"$WIN" -p '#{automatic-rename}' 2>/dev/null)
      if [ "$_auto" = "0" ]; then
        printf 'set-window-option -t :%s @tab_show_name "1"\n' "$WIN"
      else
        printf 'set-window-option -t :%s @tab_show_name ""\n' "$WIN"
      fi
      if [ "$WIN" -eq "$ACTIVE" ]; then
        NAME_BG=$(active_dark_color "$WIN")
        DK_BG=$(active_name_color "$WIN")
        # Active tab: trapezoid /name\index/ using E0BA and E0B8
        printf 'set-window-option -t :%s @tab_name_style "bg=%s,fg=%s,nobold"\n' "$WIN" "$NAME_BG" "$NOVA_FG"
        HAS_LEFT=0
        for _w in $WIN_LIST; do [ "$_w" -lt "$WIN" ] && HAS_LEFT=1; done
        if [ "$HAS_LEFT" = "1" ]; then
          printf 'set-window-option -t :%s @tab_arrow_on "bg=%s,fg=%s"\n' "$WIN" "$DK_BG" "$DK_BG"
          printf 'set-window-option -t :%s @tab_has_left "1"\n' "$WIN"
        else
          printf 'set-window-option -t :%s @tab_has_left ""\n' "$WIN"
        fi
        printf 'set-window-option -t :%s @tab_inner "bg=%s,fg=%s"\n' "$WIN" "$NAME_BG" "$DK_BG"
        printf 'set-window-option -t :%s @tab_dk_style "bg=%s,fg=%s,nobold"\n' "$WIN" "$DK_BG" "$NOVA_FG"
        printf 'set-window-option -t :%s @tab_dk_color "%s"\n' "$WIN" "$DK_BG"
        printf 'set-window-option -t :%s @tab_name_color "%s"\n' "$WIN" "$NAME_BG"
        printf 'set-window-option -t :%s @tab_claude_needs_input ""\n' "$WIN"
        printf 'set-window-option -t :%s @tab_claude_blink ""\n' "$WIN"
      else
        NAME_BG=$(active_dark_color "$WIN")
        LABEL_BG=$(active_dark_color "$WIN")
        printf 'set-window-option -t :%s @tab_name_style "bg=%s,fg=%s,nobold"\n' "$WIN" "$NAME_BG" "$NOVA_FG"
        printf 'set-window-option -t :%s @tab_inactive_color "%s"\n' "$WIN" "$NAME_BG"
        printf 'set-window-option -t :%s @tab_inactive_label_color "%s"\n' "$WIN" "$LABEL_BG"
        printf 'set-window-option -t :%s @tab_inactive_label_style "bg=%s,fg=%s,nobold"\n' "$WIN" "$LABEL_BG" "$NOVA_FG"
        printf 'set-window-option -t :%s @tab_arrow_on "bg=default,fg=%s"\n' "$WIN" "$NAME_BG"
        has_left=0
        for _w in $WIN_LIST; do [ "$_w" -lt "$WIN" ] && has_left=1; done
        if [ "$has_left" = "1" ]; then
          printf 'set-window-option -t :%s @tab_has_left "1"\n' "$WIN"
        else
          printf 'set-window-option -t :%s @tab_has_left ""\n' "$WIN"
        fi
      fi
      RN=$(right_neighbor "$WIN")
      if [ -z "$RN" ]; then
        printf 'set-window-option -t :%s @tab_arrow_off "bg=default,fg=%s"\n' "$WIN" "$NAME_BG"
      else
        if [ "$RN" -eq "$ACTIVE" ]; then
          NEXT_BG=$(active_dark_color "$RN")
        else
          NEXT_BG="default"
        fi
        printf 'set-window-option -t :%s @tab_arrow_off "bg=%s,fg=%s"\n' "$WIN" "$NEXT_BG" "$NAME_BG"
      fi
    done
  } | tmux source-file -

}

# Git status symbols used in pane borders:
#   =  Merge conflicts
#   +  Staged changes
#   !  Modified tracked files
#   »  Renamed files
#   ✘  Deleted files
#   $  Stashed changes
#   ?  Untracked files
#   ⇡N Commits ahead of upstream
#   ⇣N Commits behind upstream
#   ⇕  Both ahead and behind
#   ✓  Tracking upstream, clean
cmd_pane_git() {
  dir="$1"
  cd "$dir" 2>/dev/null || return 0
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

  branch=$(git branch --show-current 2>/dev/null)
  [ -z "$branch" ] && branch=$(git rev-parse --short HEAD 2>/dev/null)
  [ -z "$branch" ] && return 0

  porcelain=$(git status --porcelain 2>/dev/null)
  flags=$(echo "$porcelain" | awk '
    /^[UAD][UAD]/ { conflict=1 }
    /^[^? ]/ { staged=1 }
    /^.[M]/ { modified=1 }
    /^R/ { renamed=1 }
    /^.[D]/ { deleted=1 }
    /^\?\?/ { untracked=1 }
    END { print conflict+0, staged+0, modified+0, renamed+0, deleted+0, untracked+0 }
  ')
  _stashed=0
  git stash list 2>/dev/null | grep -q . && _stashed=1
  _c=$(echo $flags | cut -d" " -f1)
  _s=$(echo $flags | cut -d" " -f2)
  _m=$(echo $flags | cut -d" " -f3)
  _r=$(echo $flags | cut -d" " -f4)
  _d=$(echo $flags | cut -d" " -f5)
  _u=$(echo $flags | cut -d" " -f6)
  all_status=""
  [ "$_c" = "1" ] && all_status="${all_status}="
  [ "$_s" = "1" ] && all_status="${all_status}+"
  [ "$_m" = "1" ] && all_status="${all_status}!"
  [ "$_r" = "1" ] && all_status="${all_status}»"
  [ "$_d" = "1" ] && all_status="${all_status}✘"
  [ "$_stashed" = "1" ] && all_status="${all_status}\$"
  [ "$_u" = "1" ] && all_status="${all_status}?"

  ahead_behind=""
  if git rev-parse --verify "@{u}" >/dev/null 2>&1; then
    ahead=$(git rev-list --count "@{u}..HEAD" 2>/dev/null || echo 0)
    behind=$(git rev-list --count "HEAD..@{u}" 2>/dev/null || echo 0)
    if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
      ahead_behind="⇕"
    elif [ "$ahead" -gt 0 ]; then
      ahead_behind="⇡${ahead}"
    elif [ "$behind" -gt 0 ]; then
      ahead_behind="⇣${behind}"
    fi
  fi

  combined="${all_status}${ahead_behind}"
  if [ -n "$combined" ]; then
    printf '  %s %s' "$branch" "$combined"
  elif git rev-parse --verify "@{u}" >/dev/null 2>&1; then
    printf '  %s ✓' "$branch"
  else
    printf '  %s' "$branch"
  fi
}

cmd_pane_border() {
  # Takes pane_current_path as $1; outputs a complete tmux format string.
  # Called via #() in pane-border-format so it refreshes every status-interval.
  pane_path="$1"
  CWD_BG=$NOVA_DIR      # Match starship directory bg
  BRANCH_BG=$NOVA_BRANCH # Match starship git branch bg

  short_path=$(printf '%s' "$pane_path" | sed "s|$HOME|~|" | awk -F'/' '{n=NF; if(n>=2) print $(n-1)"/"$n; else print $n}')

  branch=""
  chips=""

  if [ -n "$pane_path" ] && cd "$pane_path" 2>/dev/null && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    branch=$(git branch --show-current 2>/dev/null)
    [ -z "$branch" ] && branch=$(git rev-parse --short HEAD 2>/dev/null)

    if [ -n "$branch" ]; then
      porcelain=$(git status --porcelain 2>/dev/null)

      # Blue: stash entries exist
      stashed=0
      git stash list 2>/dev/null | grep -q . && stashed=1

      # Red: uncommitted local changes (unstaged modified/deleted or untracked)
      has_red=0
      printf '%s\n' "$porcelain" | grep -qE '^.[MD]' && has_red=1
      printf '%s\n' "$porcelain" | grep -q '^[?][?]'  && has_red=1

      # Yellow: staged index changes OR unpushed commits
      has_yellow=0
      printf '%s\n' "$porcelain" | grep -qE '^[MADRCU]' && has_yellow=1
      has_upstream=0; ahead=0; behind=0
      if git rev-parse --verify "@{u}" >/dev/null 2>&1; then
        has_upstream=1
        ahead=$(git rev-list --count "@{u}..HEAD" 2>/dev/null || echo 0)
        behind=$(git rev-list --count "HEAD..@{u}" 2>/dev/null || echo 0)
        [ "$ahead" -gt 0 ] && has_yellow=1
      fi

      # Green: fully synced — no stash, clean working tree, not ahead, not behind
      has_green=0
      if [ "$stashed" = "0" ] && [ "$has_red" = "0" ] && [ "$has_yellow" = "0" ] && \
         [ "$has_upstream" = "1" ] && [ "$behind" = "0" ]; then
        has_green=1
      fi

      # Chips in order: blue > red > yellow > green
      [ "$stashed" = "1" ]    && chips="${chips}#[bg=${NOVA_GIT_BLUE}] #[default]"
      [ "$has_red" = "1" ]    && chips="${chips}#[bg=${NOVA_GIT_RED}] #[default]"
      [ "$has_yellow" = "1" ] && chips="${chips}#[bg=${NOVA_GIT_YELLOW}] #[default]"
      [ "$has_green" = "1" ]  && chips="${chips}#[bg=${NOVA_GIT_GREEN}] #[default]"
    fi
  fi

  if [ -n "$branch" ]; then
    printf '%s' "#[bg=${CWD_BG},fg=${NOVA_FG}] ${short_path} #[default] #[bg=${BRANCH_BG},fg=${NOVA_FG}] ${branch} #[default]${chips}"
  else
    printf '%s' "#[bg=${CWD_BG},fg=${NOVA_FG}] ${short_path} #[default]"
  fi
}

cmd_pane_colors() {
  # Legacy hook-based updater — kept for backward compat.
  # The live path now runs via #() in pane-border-format.
  pane_id=$(tmux display-message -p '#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null)
  pane_path=$(tmux display-message -p '#{pane_current_path}' 2>/dev/null)
  fmt=$(cmd_pane_border "$pane_path")
  tmux set-option -pt "$pane_id" @pane_border_fmt "$fmt" 2>/dev/null || true
}

cmd_tab_blink_start() {
  WIN="$1"
  PID_FILE="/tmp/claude-blink-${WIN}"
  # Kill any existing blink manager for this window
  if [ -f "$PID_FILE" ]; then
    kill "$(cat "$PID_FILE")" 2>/dev/null
    rm -f "$PID_FILE"
  fi
  (
    while [ "$(tmux display-message -t :"$WIN" -p '#{@tab_claude_needs_input}' 2>/dev/null)" = "1" ]; do
      tmux set-window-option -t :"$WIN" @tab_claude_blink '1' 2>/dev/null
      tmux refresh-client -S 2>/dev/null
      sleep 0.6
      tmux set-window-option -t :"$WIN" @tab_claude_blink '' 2>/dev/null
      tmux refresh-client -S 2>/dev/null
      sleep 0.6
    done
    tmux set-window-option -t :"$WIN" @tab_claude_blink '' 2>/dev/null
    tmux refresh-client -S 2>/dev/null
    rm -f "$PID_FILE"
  ) >/dev/null 2>&1 </dev/null &
  printf '%s\n' "$!" >"$PID_FILE"
}

case "${1:-}" in
  status-right)             cmd_status_right ;;
  dir)                      shift; cmd_dir "$@" ;;
  pane-git)                 shift; cmd_pane_git "$@" ;;
  pane-border)              shift; cmd_pane_border "$@" ;;
  pane-colors)              cmd_pane_colors ;;
  tab-colors)               cmd_tab_colors ;;
  tab-blink-start)  shift; cmd_tab_blink_start "$@" ;;
esac
