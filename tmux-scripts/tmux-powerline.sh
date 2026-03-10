#!/bin/sh
# tmux-powerline.sh - Unified tmux powerline layout
# All formatting, glyphs, and colors centralized here.
# Raw data from tmux-data.sh; styling applied by this script.
# Usage: tmux-powerline.sh <command> [args...]
# Commands: status-right, dir <path>, pane-git <path>, pane-colors, tab-colors

cmd_status_right() {
  TERM_BG="#282c34"
  DATA="$HOME/dotFiles/tmux-scripts/tmux-data.sh"

  cpu_val=$("$DATA" cpu)
  mem_val=$("$DATA" mem)
  bat_raw=$("$DATA" bat)

  case "$bat_raw" in
    ⚡*) bat_charging="⚡"; bat_val="${bat_raw#⚡}" ;;
    *)      bat_charging="";      bat_val="$bat_raw" ;;
  esac

  # Purple gradient (6 stages, rightmost=brightest):
  #   Stage  Act Value  Act Label  Inact Value  Inact Label
  #     #1   #6f558c    #57436e    #78737d       #7c7585
  #     #2   #634c7c    #4b3a5e    #6c6770       #706977
  #     #3   #56426d    #3e304f    #5f5b63       #635d6a
  #     #4   #4a395d    #32273f    #534f56       #57525d
  #     #5   #3e2f4e    #261d30    #464349       #4a464f
  #     #6   #31263e    #1a1420    #3a373c       #3e3a42
  # Mapping: TIME=#1  BAT=#2  MEM=#3  CPU=#4
  if [ "$cpu_val" -gt 80 ]; then CPU_BG="#6a2c2c"; CPU_DK="#481e1e"
  elif [ "$cpu_val" -gt 50 ]; then CPU_BG="#745d22"; CPU_DK="#4f3f17"
  else CPU_BG="#69402d"; CPU_DK="#472b1f"
  fi
  MEM_BG="#3a5875"; MEM_DK="#2d4052"
  if [ "$bat_val" -gt 50 ]; then BAT_BG="#438567"; BAT_DK="#33654e"
  elif [ "$bat_val" -gt 20 ]; then BAT_BG="#9a7c2e"; BAT_DK="#755e23"
  else BAT_BG="#8d3b3b"; BAT_DK="#6b2d2d"
  fi
  TIME_BG="#6f558c"; TIME_DK="#57436e"

  _dt=$(date '+%-l:%M %p|%a %b %-d')
  time_val="${_dt%%|*}"
  date_val=$(echo "${_dt#*|}" | tr 'a-z' 'A-Z')

  cpu_display=$(printf '%4s' "${cpu_val}%")
  mem_display=$(printf '%4s' "${mem_val}")
  bat_display=$(printf '%4s' "${bat_charging}${bat_val}%")

  SL=""
  BS=""

  o="#[bg=${CPU_BG},fg=${TERM_BG}]${SL}"
  o="${o}#[bg=${CPU_BG},fg=#f0f0f0] ${cpu_display} "
  o="${o}#[bg=${CPU_BG},fg=${CPU_DK}]${BS}"
  o="${o}#[bg=${CPU_DK},fg=#f0f0f0,nobold] CPU "

  o="${o}#[bg=${CPU_DK},fg=${TERM_BG}]${BS}"
  o="${o}#[bg=${MEM_BG},fg=${TERM_BG}]${SL}"
  o="${o}#[bg=${MEM_BG},fg=#f0f0f0] ${mem_display} "
  o="${o}#[bg=${MEM_BG},fg=${MEM_DK}]${BS}"
  o="${o}#[bg=${MEM_DK},fg=#f0f0f0,nobold] MEM "

  o="${o}#[bg=${MEM_DK},fg=${TERM_BG}]${BS}"
  o="${o}#[bg=${BAT_BG},fg=${TERM_BG}]${SL}"
  o="${o}#[bg=${BAT_BG},fg=#f0f0f0] ${bat_display} "
  o="${o}#[bg=${BAT_BG},fg=${BAT_DK}]${BS}"
  o="${o}#[bg=${BAT_DK},fg=#f0f0f0,nobold] BAT "

  o="${o}#[bg=${BAT_DK},fg=${TERM_BG}]${BS}"
  o="${o}#[bg=${TIME_BG},fg=${TERM_BG}]${SL}"
  o="${o}#[bg=${TIME_BG},fg=#ffffff] ${time_val} "
  o="${o}#[bg=${TIME_BG},fg=${TIME_DK}]${BS}"
  o="${o}#[bg=${TIME_DK},fg=#ffffff,nobold] ${date_val} "

  printf '%s' "$o"
}

cmd_dir() {
  # Returns last 2 path components (matches starship truncation_length=2)
  p=$(echo "$1" | sed "s|^$HOME|~|")
  echo "$p" | awk -F'/' '{n=NF; if(n>=2) print $(n-1)"/"$n; else print $n}'

}


cmd_tab_colors() {
  TERM_BG="#282c34"
  _info=$(tmux display-message -p '#{window_index}|#{W:#{window_index} }' 2>/dev/null || echo "1|1 ")
  ACTIVE="${_info%%|*}"
  WIN_LIST=$(printf '%s\n' "${_info#*|}" | tr ' ' '\n' | grep -v '^$' | sort -n)
  active_color() {
    case "$(( (($1-1)%6)+1 ))" in
      1) printf '#8f5922' ;;
      2) printf '#7b4d1d' ;;
      3) printf '#674118' ;;
      4) printf '#523614' ;;
      5) printf '#3e2a0f' ;;
      6) printf '#2a1e0a' ;;
    esac
  }
  active_dark_color() {
    case "$(( (($1-1)%6)+1 ))" in
      1) printf '#71411a' ;;
      2) printf '#5d3515' ;;
      3) printf '#492910' ;;
      4) printf '#341e0c' ;;
      5) printf '#201207' ;;
      6) printf '#0c0602' ;;
    esac
  }
  inactive_color() {
    case "$(( (($1-1)%6)+1 ))" in
      1) printf '#6d6359' ;;
      2) printf '#5e554d' ;;
      3) printf '#4f4841' ;;
      4) printf '#403a34' ;;
      5) printf '#312d28' ;;
      6) printf '#221f1c' ;;
    esac
  }
  inactive_label_color() {
    # inactive_id + delta(+15,+12,+4) — half the active delta
    # Gives L1 contrast 3.37:1 vs #f0f0f0, well above 3:1 for all levels
    case "$(( (($1-1)%6)+1 ))" in
      1) printf '#7c6f5d' ;;
      2) printf '#6d6151' ;;
      3) printf '#5e5445' ;;
      4) printf '#4f4638' ;;
      5) printf '#40392c' ;;
      6) printf '#312b20' ;;
    esac
  }
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
        NAME_BG=$(active_color "$WIN")
        DK_BG=$(active_dark_color "$WIN")
        # Active tab: trapezoid /name\index/ using E0BA and E0B8
        printf 'set-window-option -t :%s @tab_name_style "bg=%s,fg=#f0f0f0,bold"\n' "$WIN" "$NAME_BG"
        HAS_LEFT=0
        for _w in $WIN_LIST; do [ "$_w" -lt "$WIN" ] && HAS_LEFT=1; done
        if [ "$HAS_LEFT" = "1" ]; then
          printf 'set-window-option -t :%s @tab_arrow_on "bg=%s,fg=%s"\n' "$WIN" "$DK_BG" "$DK_BG"
          printf 'set-window-option -t :%s @tab_has_left "1"\n' "$WIN"
        else
          printf 'set-window-option -t :%s @tab_has_left ""\n' "$WIN"
        fi
        printf 'set-window-option -t :%s @tab_inner "bg=%s,fg=%s"\n' "$WIN" "$NAME_BG" "$DK_BG"
        printf 'set-window-option -t :%s @tab_dk_style "bg=%s,fg=#f0f0f0,nobold"\n' "$WIN" "$DK_BG"
        printf 'set-window-option -t :%s @tab_dk_color "%s"\n' "$WIN" "$DK_BG"
        printf 'set-window-option -t :%s @tab_name_color "%s"\n' "$WIN" "$NAME_BG"
      else
        NAME_BG=$(inactive_color "$WIN")
        LABEL_BG=$(inactive_label_color "$WIN")
        printf 'set-window-option -t :%s @tab_name_style "bg=%s,fg=#cccccc,nobold"\n' "$WIN" "$NAME_BG"
        printf 'set-window-option -t :%s @tab_inactive_color "%s"\n' "$WIN" "$NAME_BG"
        printf 'set-window-option -t :%s @tab_inactive_label_color "%s"\n' "$WIN" "$LABEL_BG"
        printf 'set-window-option -t :%s @tab_inactive_label_style "bg=%s,fg=#f0f0f0,nobold"\n' "$WIN" "$LABEL_BG"
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
  CWD_BG="#a86828"    # Match starship directory bg (active tab orange)
  BRANCH_BG="#494949" # Match starship git_branch bg

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
      [ "$stashed" = "1" ]    && chips="${chips}#[bg=#61afef] #[default]"
      [ "$has_red" = "1" ]    && chips="${chips}#[bg=#e06c75] #[default]"
      [ "$has_yellow" = "1" ] && chips="${chips}#[bg=#e5c07b] #[default]"
      [ "$has_green" = "1" ]  && chips="${chips}#[bg=#98c379] #[default]"
    fi
  fi

  if [ -n "$branch" ]; then
    printf '%s' "#[bg=${CWD_BG},fg=#f0f0f0] ${short_path} #[default] #[bg=${BRANCH_BG},fg=#f0f0f0] ${branch} #[default]${chips}"
  else
    printf '%s' "#[bg=${CWD_BG},fg=#f0f0f0] ${short_path} #[default]"
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

case "${1:-}" in
  status-right)  cmd_status_right ;;
  dir)           shift; cmd_dir "$@" ;;
  pane-git)      shift; cmd_pane_git "$@" ;;
  pane-border)   shift; cmd_pane_border "$@" ;;
  pane-colors)   cmd_pane_colors ;;
  tab-colors)    cmd_tab_colors ;;
esac
