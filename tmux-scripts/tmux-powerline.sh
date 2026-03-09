#!/bin/sh
# tmux-powerline.sh - Unified tmux powerline layout
# All formatting, glyphs, and colors centralized here.
# Raw data from tmux-data.sh; styling applied by this script.
# Usage: tmux-powerline.sh <command> [args...]
# Commands: status-right, dir <path>, git <path>, tab-colors

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
  TIME_BG="#A884D4"; TIME_DK="#6d568a"

  time_val=$(date '+%-l:%M %p')
  date_val=$(date '+%a %b %-d' | tr 'a-z' 'A-Z')

  SL=""
  BS=""

  o="#[bg=${TERM_BG},fg=${CPU_BG}]${SL}"
  o="${o}#[bg=${CPU_BG},fg=#f0f0f0] ${cpu_val}% "
  o="${o}#[bg=${CPU_DK},fg=${CPU_BG}]${BS}"
  o="${o}#[bg=${CPU_DK},fg=#f0f0f0,nobold] CPU "

  o="${o}#[bg=${CPU_DK},fg=${MEM_BG}]${SL}"
  o="${o}#[bg=${MEM_BG},fg=#f0f0f0] ${mem_val} "
  o="${o}#[bg=${MEM_DK},fg=${MEM_BG}]${BS}"
  o="${o}#[bg=${MEM_DK},fg=#f0f0f0,nobold] MEM "

  o="${o}#[bg=${MEM_DK},fg=${BAT_BG}]${SL}"
  o="${o}#[bg=${BAT_BG},fg=#f0f0f0] ${bat_charging}${bat_val}% "
  o="${o}#[bg=${BAT_DK},fg=${BAT_BG}]${BS}"
  o="${o}#[bg=${BAT_DK},fg=#f0f0f0,nobold] BAT "

  o="${o}#[bg=${BAT_DK},fg=${TIME_BG}]${SL}"
  o="${o}#[bg=${TIME_BG},fg=#ffffff] ${time_val} "
  o="${o}#[bg=${TIME_DK},fg=${TIME_BG}]${BS}"
  o="${o}#[bg=${TIME_DK},fg=#ffffff,nobold] ${date_val} "

  printf '%s' "$o"
}

cmd_dir() {
  # Returns last 2 path components (matches starship truncation_length=2)
  p=$(echo "$1" | sed "s|^$HOME|~|")
  echo "$p" | awk -F'/' '{n=NF; if(n>=2) print $(n-1)"/"$n; else print $n}'

}

cmd_git() {
  # tmux-git.sh <pane_current_path>
  # Outputs optional lang segment + git branch + status
  # Handles all transitions from purple dir background

  dir="$1"
  PURPLE="#4a4a4a"
  LABEL_BG="default"
  TERM_BG="#282c34"

  cd "$dir" 2>/dev/null || { printf '#[bg=#2e2e2e,fg=%s]' "$PURPLE"; return 0; }

  # ── Language detection ───────────────────────────────────────────────────
  lang=""
  [ -f "build.zig" ]        && lang="zig"
  [ -z "$lang" ] && [ -f "Cargo.toml" ]       && lang="rust"
  [ -z "$lang" ] && [ -f "go.mod" ]           && lang="go"
  [ -z "$lang" ] && [ -f "mix.exs" ]          && lang="elixir"
  [ -z "$lang" ] && [ -f "build.gradle.kts" ] && lang="kotlin"
  [ -z "$lang" ] && [ -f "Package.swift" ]    && lang="swift"
  [ -z "$lang" ] && [ -f "composer.json" ]    && lang="php"
  [ -z "$lang" ] && { [ -f "Gemfile" ] || [ -f ".ruby-version" ]; } && lang="ruby"
  [ -z "$lang" ] && { [ -f "deno.json" ] || [ -f "deno.jsonc" ]; } && lang="deno"
  [ -z "$lang" ] && { [ -f "package.json" ] || [ -f ".nvmrc" ] || [ -f ".node-version" ]; } && lang="node"
  [ -z "$lang" ] && { [ -f "pom.xml" ] || [ -f "build.gradle" ]; } && lang="java"
  [ -z "$lang" ] && { [ -f "pyproject.toml" ] || [ -f "setup.py" ] || [ -f "requirements.txt" ] || [ -f ".python-version" ]; } && lang="python"

  # ── Check git early ──────────────────────────────────────────────────────
  is_git=0
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 && is_git=1

  # ── No lang, no git: just close from purple ──────────────────────────────
  if [ -z "$lang" ] && [ "$is_git" = "0" ]; then
    printf '#[bg=#2e2e2e,fg=%s]' "$PURPLE"
    return 0
  fi

  # ── Lang segment ─────────────────────────────────────────────────────────
  if [ -n "$lang" ]; then
    case "$lang" in
      node)    LCOLOR="#4a9070"; LABEL="NODE";  ASDF="nodejs" ;;
      deno)    LCOLOR="#4a8a8a"; LABEL="DENO";  ASDF="deno" ;;
      python)  LCOLOR="#5f7faf"; LABEL="PY";    ASDF="python" ;;
      rust)    LCOLOR="#b06040"; LABEL="RUST";  ASDF="rust" ;;
      go)      LCOLOR="#5a9aaa"; LABEL="GO";    ASDF="golang" ;;
      ruby)    LCOLOR="#b05050"; LABEL="RUBY";  ASDF="ruby" ;;
      elixir)  LCOLOR="#7b60a0"; LABEL="EX";    ASDF="elixir" ;;
      swift)   LCOLOR="#c06048"; LABEL="SWIFT"; ASDF="" ;;
      java)    LCOLOR="#a06050"; LABEL="JAVA";  ASDF="java" ;;
      kotlin)  LCOLOR="#7f52b0"; LABEL="KT";    ASDF="kotlin" ;;
      php)     LCOLOR="#7070a8"; LABEL="PHP";   ASDF="php" ;;
      zig)     LCOLOR="#c09040"; LABEL="ZIG";   ASDF="zig" ;;
    esac

    ver=""
    if [ -n "$ASDF" ]; then
      ver=$(asdf current "$ASDF" 2>/dev/null | awk 'NR>1{print $2}')
    fi
    if [ -z "$ver" ] || [ "$ver" = "______" ]; then
      case "$lang" in
        node)    ver=$(node --version 2>/dev/null | sed 's/^v//') ;;
        deno)    ver=$(deno --version 2>/dev/null | head -1 | awk '{print $2}') ;;
        python)  ver=$(python3 --version 2>/dev/null | awk '{print $2}') ;;
        rust)    ver=$(rustc --version 2>/dev/null | awk '{print $2}') ;;
        go)      ver=$(go version 2>/dev/null | awk '{print $3}' | sed 's/^go//') ;;
        ruby)    ver=$(ruby --version 2>/dev/null | awk '{print $2}') ;;
        elixir)  ver=$(elixir --version 2>/dev/null | tail -1 | awk '{print $2}') ;;
        swift)   ver=$(swift --version 2>/dev/null | head -1 | awk '{print $4}') ;;
        java)    ver=$(java -version 2>&1 | head -1 | sed 's/.*"\(.*\)".*/\1/') ;;
        kotlin)  ver=$(kotlin -version 2>&1 | awk '{print $3}') ;;
        php)     ver=$(php --version 2>/dev/null | head -1 | awk '{print $2}') ;;
        zig)     ver=$(zig version 2>/dev/null) ;;
      esac
    fi
    [ -z "$ver" ] && ver="?"

    # [purple->dark] LABEL [dark->color] version [color->dark]
    printf '#[bg=%s,fg=%s]#[bg=%s,fg=#cccccc,nobold] %s #[bg=%s,fg=%s]#[bg=%s,fg=#f0f0f0] %s #[bg=%s,fg=%s]' \
      "$LABEL_BG" "$PURPLE" "$LABEL_BG" "$LABEL" "$LCOLOR" "$TERM_BG" "$LCOLOR" "$ver" "$LABEL_BG" "$LCOLOR"

    # If no git, close from dark
    if [ "$is_git" = "0" ]; then
      printf '#[bg=#2e2e2e,fg=%s]' "$TERM_BG"
      return 0
    fi
  else
    # No lang, has git: transition purple -> dark
    printf '#[bg=%s,fg=%s]' "$LABEL_BG" "$PURPLE"
  fi

  # ── Git branch + status (on dark bg) ────────────────────────────────────
  branch=$(git branch --show-current 2>/dev/null)
  [ -z "$branch" ] && branch=$(git rev-parse --short HEAD 2>/dev/null)
  [ -z "$branch" ] && { printf '#[bg=#2e2e2e,fg=%s]' "$TERM_BG"; return 0; }

  porcelain=$(git status --porcelain 2>/dev/null)
  conflicted=0; staged=0; modified=0; renamed=0; deleted=0; stashed=0; untracked=0
  echo "$porcelain" | grep -q '^[UAD][UAD]' 2>/dev/null && conflicted=1
  echo "$porcelain" | grep -q '^[^? ]'      2>/dev/null && staged=1
  echo "$porcelain" | grep -q '^.[M]'        2>/dev/null && modified=1
  echo "$porcelain" | grep -q '^R'           2>/dev/null && renamed=1
  echo "$porcelain" | grep -q '^.[D]'        2>/dev/null && deleted=1
  git stash list 2>/dev/null | grep -q .                 && stashed=1
  echo "$porcelain" | grep -q '^??'          2>/dev/null && untracked=1

  all_status=""
  [ "$conflicted" = "1" ] && all_status="${all_status}="
  [ "$staged"     = "1" ] && all_status="${all_status}+"
  [ "$modified"   = "1" ] && all_status="${all_status}!"
  [ "$renamed"    = "1" ] && all_status="${all_status}»"
  [ "$deleted"    = "1" ] && all_status="${all_status}✘"
  [ "$stashed"    = "1" ] && all_status="${all_status}$$"
  [ "$untracked"  = "1" ] && all_status="${all_status}?"

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

  printf '#[bg=%s,fg=#f0f0f0,nobold]  %s ' "$LABEL_BG" "$branch"

  combined="${all_status}${ahead_behind}"
  if [ -n "$combined" ]; then
    printf '#[bg=#8a6f2a,fg=%s]#[bg=#8a6f2a,fg=#f0f0f0,nobold] %s #[bg=#2e2e2e,fg=#8a6f2a]' "$TERM_BG" "$combined"
  elif git rev-parse --verify "@{u}" >/dev/null 2>&1; then
    printf '#[bg=#2e8b57,fg=%s]#[bg=#2e8b57,fg=#f0f0f0,nobold]  ✓ #[bg=#2e2e2e,fg=#2e8b57]' "$TERM_BG"
  else
    printf '#[bg=#2e2e2e,fg=%s]' "$TERM_BG"
  fi

}

cmd_tab_colors() {
  TERM_BG="#282c34"
  _info=$(tmux display-message -p '#{window_index}|#{W:#{window_index} }' 2>/dev/null || echo "1|1 ")
  ACTIVE="${_info%%|*}"
  WIN_LIST=$(printf '%s\n' "${_info#*|}" | tr ' ' '\n' | grep -v '^$' | sort -n)
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
  active_dark_color() {
    case "$(( (($1-1)%15)+1 ))" in
      1) printf '#305d48' ;;
      2) printf '#723e4e' ;;
      3) printf '#774834' ;;
      4) printf '#3d5771' ;;
      5) printf '#5a4927' ;;
      6) printf '#474e21' ;;
      7) printf '#345323' ;;
      8) printf '#255525' ;;
      9) printf '#235353' ;;
      10) printf '#41467a' ;;
      11) printf '#51447c' ;;
      12) printf '#603d78' ;;
      13) printf '#763656' ;;
      14) printf '#763842' ;;
      15) printf '#4e4e21' ;;
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
        DK_BG=$(active_dark_color "$WIN")
        # Active tab: trapezoid /name\index/ using E0BA and E0B8
        printf 'set-window-option -t :%s @tab_name_style "bg=%s,fg=#f0f0f0,bold"\n' "$WIN" "$NAME_BG"
        HAS_LEFT=0
        for _w in $WIN_LIST; do [ "$_w" -lt "$WIN" ] && HAS_LEFT=1; done
        if [ "$HAS_LEFT" = "1" ]; then
          printf 'set-window-option -t :%s @tab_arrow_on "bg=%s,fg=%s"\n' "$WIN" "$DK_BG" "$DK_BG"
        else
          printf 'set-window-option -t :%s @tab_arrow_on "bg=%s,fg=%s"\n' "$WIN" "$DK_BG" "$TERM_BG"
        fi
        printf 'set-window-option -t :%s @tab_inner "bg=%s,fg=%s"\n' "$WIN" "$DK_BG" "$NAME_BG"
        printf 'set-window-option -t :%s @tab_dk_style "bg=%s,fg=#f0f0f0,nobold"\n' "$WIN" "$DK_BG"
        printf 'set-window-option -t :%s @tab_arrow_off "bg=#4a4a4a,fg=%s"\n' "$WIN" "$NAME_BG"
      else
        NAME_BG="#4a4a4a"
        printf 'set-window-option -t :%s @tab_name_style "bg=%s,fg=#cccccc,nobold"\n' "$WIN" "$NAME_BG"
        printf 'set-window-option -t :%s @tab_arrow_on "bg=%s,fg=%s"\n' "$WIN" "$NAME_BG" "#2e2e2e"
      fi
      RN=$(right_neighbor "$WIN")
      if [ "$WIN" -eq "$ACTIVE" ]; then
        : # arrow_off already set above
      elif [ -z "$RN" ]; then
        printf 'set-window-option -t :%s @tab_arrow_off "bg=default,fg=%s"\n' "$WIN" "$NAME_BG"
      else
        if [ "$RN" -eq "$ACTIVE" ]; then
          NEXT_BG=$(active_dark_color "$RN")
        else
          NEXT_BG="#2e2e2e"
        fi
        printf 'set-window-option -t :%s @tab_arrow_off "bg=%s,fg=%s"\n' "$WIN" "$NEXT_BG" "$NAME_BG"
      fi
    done
  } | tmux source-file -

}

case "${1:-}" in
  status-right) cmd_status_right ;;
  dir)          shift; cmd_dir "$@" ;;
  git)          shift; cmd_git "$@" ;;
  tab-colors)   cmd_tab_colors ;;
esac
