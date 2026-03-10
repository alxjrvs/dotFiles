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

  if [ "$cpu_val" -gt 80 ]; then CPU_BG="#c05050"; CPU_DK="#7d3434"
  elif [ "$cpu_val" -gt 50 ]; then CPU_BG="#8a6f2a"; CPU_DK="#5a481b"
  else CPU_BG="#b87050"; CPU_DK="#784934"
  fi
  MEM_BG="#5f87af"; MEM_DK="#3e5770"
  if [ "$bat_val" -gt 50 ]; then BAT_BG="#4a9070"; BAT_DK="#305e49"
  elif [ "$bat_val" -gt 20 ]; then BAT_BG="#8a6f2a"; BAT_DK="#5a481b"
  else BAT_BG="#c05050"; BAT_DK="#7d3434"
  fi
  TIME_BG="#8a6ab8"; TIME_DK="#57436e"

  _dt=$(date '+%-l:%M %p|%a %b %-d')
  time_val="${_dt%%|*}"
  date_val=$(echo "${_dt#*|}" | tr 'a-z' 'A-Z')

  SL=""
  BS=""

  o="#[bg=${CPU_BG},fg=${TERM_BG}]${SL}"
  o="${o}#[bg=${CPU_BG},fg=#f0f0f0] ${cpu_val}% "
  o="${o}#[bg=${CPU_BG},fg=${CPU_DK}]${BS}"
  o="${o}#[bg=${CPU_DK},fg=#f0f0f0,nobold] CPU "

  o="${o}#[bg=${CPU_DK},fg=${TERM_BG}]${BS}"
  o="${o}#[bg=${MEM_BG},fg=${TERM_BG}]${SL}"
  o="${o}#[bg=${MEM_BG},fg=#f0f0f0] ${mem_val} "
  o="${o}#[bg=${MEM_BG},fg=${MEM_DK}]${BS}"
  o="${o}#[bg=${MEM_DK},fg=#f0f0f0,nobold] MEM "

  o="${o}#[bg=${MEM_DK},fg=${TERM_BG}]${BS}"
  o="${o}#[bg=${BAT_BG},fg=${TERM_BG}]${SL}"
  o="${o}#[bg=${BAT_BG},fg=#f0f0f0] ${bat_charging}${bat_val}% "
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
      1) printf '#a86828' ;;
      2) printf '#8f5922' ;;
      3) printf '#764a1c' ;;
      4) printf '#5c3c16' ;;
      5) printf '#432d10' ;;
      6) printf '#2a1e0a' ;;
    esac
  }
  active_dark_color() {
    case "$(( (($1-1)%6)+1 ))" in
      1) printf '#8a5020' ;;
      2) printf '#71411a' ;;
      3) printf '#583214' ;;
      4) printf '#3e240e' ;;
      5) printf '#251508' ;;
      6) printf '#0c0602' ;;
    esac
  }
  inactive_color() {
    case "$(( (($1-1)%6)+1 ))" in
      1) printf '#807468' ;;
      2) printf '#6d6359' ;;
      3) printf '#5a524a' ;;
      4) printf '#48413b' ;;
      5) printf '#35302b' ;;
      6) printf '#221f1c' ;;
    esac
  }
  inactive_label_color() {
    # inactive_id + delta(+15,+12,+4) — half the active delta
    # Gives L1 contrast 3.37:1 vs #f0f0f0, well above 3:1 for all levels
    case "$(( (($1-1)%6)+1 ))" in
      1) printf '#8f806c' ;;
      2) printf '#7c6f5d' ;;
      3) printf '#695e4e' ;;
      4) printf '#574d3f' ;;
      5) printf '#443c2f' ;;
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
