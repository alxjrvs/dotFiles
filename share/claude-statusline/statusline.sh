#!/usr/bin/env bash
# claude-statusline — a self-contained Claude Code statusline.
#
# Drop-in: needs only `git` and `jq` on PATH. No extra binaries.
# Point Claude Code at it in ~/.claude/settings.json:
#
#   "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" }
#
# Reads the Claude Code statusline JSON on stdin and emits 3–6 colored lines:
#   Line 1: repo/dir [ branch] [ worktree] [ #N: state] [C: counters] [+N/-M]
#   Line 2: [M: model] [E: effort]
#   Line 3: CTX  <bar w/ amber autocompact cell> N% [AC] [200k+]
#   Line 4: 5h   <bar> N% [time left] [delta]
#   Line 5: 7d   <bar> N% [time left] [delta]
#   Line 6: [$cost ($/h) · today $X]
#
# Line 1 uses Nerd Font glyphs — install a Nerd Font (https://nerdfonts.com)
# or they render as tofu boxes. Everything is degrade-gracefully: missing
# fields just drop their segment.
#
# Bash 3.2 compatible (macOS system bash).

# ── Byte-sequence primitives (bash 3.2 has no $'\uXXXX') ──────────────────
ESC=$(printf '\033')
BEL=$(printf '\007')
PIP_FILL=$(printf '\xe2\x96\xb0')       # ▰  U+25B0
PIP_EMPTY=$(printf '\xe2\x96\xb1')      # ▱  U+25B1
PIP_OVERFLOW='!'                        # burn-projection overflow marker (rendered bold red)
GLYPH_BRANCH=$(printf '\xee\x82\xa0')   #   U+E0A0  powerline branch
GLYPH_WORKTREE=$(printf '\xef\x83\xa8') #  U+F0E8  fa sitemap
GLYPH_PR=$(printf '\xef\x90\x87')       #   U+F407  octicon git-pull-request
EMDASH=$(printf '\xe2\x80\x94')         # —  U+2014

# ── Style primitives ──────────────────────────────────────────────────────
UNDIM="${ESC}[22m"
BOLD="${ESC}[1m"
RST="${ESC}[0m"
MUTED="${ESC}[90m"
RED="${ESC}[31m"
GREEN="${ESC}[32m"
YELLOW="${ESC}[33m"
BLUE="${ESC}[34m"
MAGENTA="${ESC}[35m"
CYAN="${ESC}[36m"
NEAR_WHITE="${ESC}[38;2;235;235;235m"
MARKER="${ESC}[38;2;96;200;255m"     # rate-window clock pip (blue)
PROJ="${ESC}[38;2;255;210;80m"       # burn projection pip (yellow)
AUTOCOMPACT="${ESC}[38;2;255;128;0m" # autocompact threshold cell (amber)

DEFAULT_PIP_COUNT=30

# ── Helpers ────────────────────────────────────────────────────────────────

# Integer prefix of a string ("42.7" → 42, "" / garbage → 0).
int_prefix() {
  local s=${1%%.*}
  case "$s" in
    '' | *[!0-9-]*) echo 0 ;;
    *) echo "$s" ;;
  esac
}

# Build an OSC8 hyperlink: osc8 <url> <text>
osc8() { printf '%s]8;;%s%s%s%s]8;;%s' "$ESC" "$1" "$BEL" "$2" "$ESC" "$BEL"; }

# Discrete bar width from terminal columns (mirrors pip_count_for_width).
pip_count_for_width() {
  local c=$1
  if [ -z "$c" ]; then
    echo "$DEFAULT_PIP_COUNT"
    return
  fi
  if [ "$c" -lt 60 ]; then
    echo 15
  elif [ "$c" -lt 90 ]; then
    echo 20
  elif [ "$c" -lt 120 ]; then
    echo 30
  elif [ "$c" -lt 160 ]; then
    echo 40
  else echo 50; fi
}

# Blackbody-style gradient at t (0..10000); sets globals _GR/_GG/_GB.
gradient_at() {
  local t=$1 u
  if [ "$t" -le 3500 ]; then
    u=$((t * 10000 / 3500))
    _GR=$((74 + (176 - 74) * u / 10000))
    _GG=$((79 + (74 - 79) * u / 10000))
    _GB=$((92 + (58 - 92) * u / 10000))
  elif [ "$t" -le 7000 ]; then
    u=$(((t - 3500) * 10000 / 3500))
    _GR=$((176 + (240 - 176) * u / 10000))
    _GG=$((74 + (160 - 74) * u / 10000))
    _GB=$((58 + (64 - 58) * u / 10000))
  elif [ "$t" -le 9000 ]; then
    u=$(((t - 7000) * 10000 / 2000))
    _GR=$((240 + (255 - 240) * u / 10000))
    _GG=$((160 + (232 - 160) * u / 10000))
    _GB=$((64 + (144 - 64) * u / 10000))
  else
    u=$(((t - 9000) * 10000 / 1000))
    _GR=255
    _GG=$((232 + (255 - 232) * u / 10000))
    _GB=$((144 + (255 - 144) * u / 10000))
  fi
}

# render_bar <pct> <marker_pct|""> <proj_pct|""> <cols|""> <marker_color>
render_bar() {
  local pct=$1 marker_pct=$2 proj_pct=$3 cols=$4 marker_color=$5
  local pip_count
  pip_count=$(pip_count_for_width "$cols")
  [ "$pct" -lt 0 ] && pct=0
  local filled=$((pct * pip_count / 100))
  [ "$filled" -gt "$pip_count" ] && filled=$pip_count
  if [ "$pct" -gt 0 ] && [ "$filled" -eq 0 ]; then filled=1; fi

  local marker_idx=-1 marker_expired=0
  if [ -n "$marker_pct" ]; then
    if [ "$marker_pct" -ge 100 ]; then
      marker_idx=$((pip_count - 1))
      marker_expired=1
    else
      local m=$marker_pct
      [ "$m" -lt 0 ] && m=0
      marker_idx=$((m * pip_count / 100))
      [ "$marker_idx" -gt $((pip_count - 1)) ] && marker_idx=$((pip_count - 1))
    fi
  fi
  local proj_idx=-1 proj_overflow=0
  if [ -n "$proj_pct" ] && [ "$proj_pct" -ge 0 ]; then
    if [ "$proj_pct" -gt 100 ]; then
      # Projection runs off the right edge: pin to the last cell, flag overflow.
      proj_idx=$((pip_count - 1))
      proj_overflow=1
    else
      proj_idx=$((proj_pct * pip_count / 100))
      [ "$proj_idx" -gt $((pip_count - 1)) ] && proj_idx=$((pip_count - 1))
    fi
  fi

  local out="" i pip
  for ((i = 0; i < pip_count; i++)); do
    if [ "$i" -lt "$filled" ]; then pip=$PIP_FILL; else pip=$PIP_EMPTY; fi
    if [ "$i" -eq "$marker_idx" ]; then
      if [ "$marker_expired" -eq 1 ]; then
        out="${out}${UNDIM}${RED}${pip}"
      else
        out="${out}${UNDIM}${marker_color}${pip}"
      fi
    elif [ "$i" -eq "$proj_idx" ]; then
      if [ "$proj_overflow" -eq 1 ]; then
        out="${out}${UNDIM}${BOLD}${RED}${PIP_OVERFLOW}"
      else
        out="${out}${UNDIM}${PROJ}${pip}"
      fi
    elif [ "$i" -lt "$filled" ]; then
      gradient_at $((i * 10000 / (pip_count - 1)))
      out="${out}${UNDIM}${ESC}[38;2;${_GR};${_GG};${_GB}m${pip}"
    else
      out="${out}${MUTED}${pip}"
    fi
  done
  printf '%s%s' "$out" "$RST"
}

# Color for a PR review_state (case-insensitive).
pr_state_color() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    approved) printf '%s' "$GREEN" ;;
    changes_requested) printf '%s' "$RED" ;;
    review_required | pending) printf '%s' "$YELLOW" ;;
    commented) printf '%s' "$CYAN" ;;
    *) printf '%s' "$MUTED" ;;
  esac
}

# Last two path components, with $HOME → ~ (mirrors last_two_components).
dir_display() {
  local p=$1 home=$HOME shown rel
  if [ -n "$home" ] && [ "${p#"$home"}" != "$p" ]; then
    rel=${p#"$home"}
    if [ -z "$rel" ]; then shown="~"; else shown="~$rel"; fi
  else
    shown=$p
  fi
  local IFS='/' x
  local -a parts clean
  read -ra parts <<< "$shown"
  clean=()
  for x in "${parts[@]}"; do [ -n "$x" ] && clean+=("$x"); done
  local n=${#clean[@]}
  case "$shown" in
    '~'*)
      if [ "$n" -ge 3 ]; then printf '%s/%s' "${clean[n - 2]}" "${clean[n - 1]}"; else printf '%s' "$shown"; fi
      ;;
    *)
      if [ "$n" -ge 2 ]; then printf '%s/%s' "${clean[n - 2]}" "${clean[n - 1]}"; else printf '%s' "$shown"; fi
      ;;
  esac
}

# ── Read stdin payload ──────────────────────────────────────────────────────
input=$(cat)

if ! command -v jq > /dev/null 2>&1; then
  printf '%sclaude-statusline: jq not found on PATH%s\n' "$RED" "$RST"
  exit 0
fi

# Pull every field in one jq pass as name-keyed key=value lines, parsed by
# `case` (bash 3.2 safe). Name-keyed beats positional: a Claude Code schema
# addition or a local reorder can't silently shift every field — unknown keys
# are ignored, missing keys keep their default.
fields=$(printf '%s' "$input" | jq -r '
  "used_pct=\(.context_window.used_percentage // "" | tostring)",
  "worktree_name=\(.worktree.name // "")",
  "project_dir=\(.workspace.project_dir // "")",
  "cwd=\(.workspace.current_dir // "")",
  "model_name=\(.model.display_name // "")",
  "effort_level=\(.effort.level // "")",
  "cost_usd=\(.cost.total_cost_usd // "" | tostring)",
  "duration_ms=\(.cost.total_duration_ms // 0 | tostring)",
  "lines_added=\(.cost.total_lines_added // 0 | tostring)",
  "lines_removed=\(.cost.total_lines_removed // 0 | tostring)",
  "pr_number=\(.pr.number // "" | tostring)",
  "pr_state=\(.pr.review_state // "")",
  "exceeds_200k=\(if .exceeds_200k_tokens == true then "1" else "" end)",
  "five_pct=\(.rate_limits.five_hour.used_percentage // "" | tostring)",
  "five_resets_at=\(.rate_limits.five_hour.resets_at // "" | tostring)",
  "seven_pct=\(.rate_limits.seven_day.used_percentage // "" | tostring)",
  "seven_resets_at=\(.rate_limits.seven_day.resets_at // "" | tostring)",
  "cols=\((.columns // .terminal.columns) // "" | tostring)"
' 2> /dev/null)

used_pct="" worktree_name_input="" project_dir="" cwd_input=""
model_name="" effort_level="" cost_usd="" duration_ms=0 lines_added=0
lines_removed=0 pr_number="" pr_state="" exceeds_200k="" five_pct=""
five_resets_at="" seven_pct="" seven_resets_at="" cols=""

while IFS= read -r _kv || [ -n "$_kv" ]; do
  case "$_kv" in *=*) ;; *) continue ;; esac
  _k=${_kv%%=*}
  _v=${_kv#*=}
  case "$_k" in
    used_pct) used_pct=$_v ;;
    worktree_name) worktree_name_input=$_v ;;
    project_dir) project_dir=$_v ;;
    cwd) cwd_input=$_v ;;
    model_name) model_name=$_v ;;
    effort_level) effort_level=$_v ;;
    cost_usd) cost_usd=$_v ;;
    duration_ms) duration_ms=$_v ;;
    lines_added) lines_added=$_v ;;
    lines_removed) lines_removed=$_v ;;
    pr_number) pr_number=$_v ;;
    pr_state) pr_state=$_v ;;
    exceeds_200k) exceeds_200k=$_v ;;
    five_pct) five_pct=$_v ;;
    five_resets_at) five_resets_at=$_v ;;
    seven_pct) seven_pct=$_v ;;
    seven_resets_at) seven_resets_at=$_v ;;
    cols) cols=$_v ;;
  esac
done <<< "$fields"

# Normalize numeric-ish fields.
duration_ms=$(int_prefix "$duration_ms")
lines_added=$(int_prefix "$lines_added")
lines_removed=$(int_prefix "$lines_removed")
case "$cols" in '' | *[!0-9]*) cols="" ;; esac

# ── Gather git state (self-contained; deliberately not the git-data cache) ──
# GIT_OPTIONAL_LOCKS=0: this runs on every refresh in the background — it must
# never contend for index.lock with the session's own git rebase/add.
export GIT_OPTIONAL_LOCKS=0
git_is_repo=0 branch="" repo_https="" repo_name="" git_worktree_name=""
ahead=0 behind=0 staged=0 unstaged=0 untracked=0 conflict=0 stash=0

if topl=$(git rev-parse --show-toplevel 2> /dev/null) && [ -n "$topl" ]; then
  git_is_repo=1
  gdir=$(git rev-parse --git-dir 2> /dev/null)
  cdir=$(git rev-parse --git-common-dir 2> /dev/null)
  [ "$gdir" != "$cdir" ] && git_worktree_name=$(basename "$topl")

  while IFS= read -r line; do
    case "$line" in
      '# branch.head '*) branch=${line#\# branch.head } ;;
      '# branch.ab '*)
        ab=${line#\# branch.ab }
        a=${ab%% *}
        b=${ab#* }
        a=${a#+}
        b=${b#-}
        [ -n "$a" ] && ahead=$a
        [ -n "$b" ] && behind=$b
        ;;
      '? '*) untracked=$((untracked + 1)) ;;
      '1 '* | '2 '* | 'u '*)
        # Second whitespace token is the XY status pair.
        # shellcheck disable=SC2086  # intentional word-split into positional params
        set -- $line
        xy=$2
        x=${xy:0:1}
        y=${xy:1:1}
        case "$xy" in
          UU | AA | DD | AU | UA | DU | UD)
            conflict=$((conflict + 1))
            continue
            ;;
        esac
        case "$x" in M | A | D | R | C) staged=$((staged + 1)) ;; esac
        case "$y" in M | D) unstaged=$((unstaged + 1)) ;; esac
        ;;
    esac
  done < <(git status --porcelain=v2 --branch 2> /dev/null)

  # Detached HEAD fallback.
  if [ -z "$branch" ] || [ "$branch" = "(detached)" ]; then
    branch=$(git rev-parse --short HEAD 2> /dev/null)
  fi

  # Remote URL → HTTPS + repo name.
  remote=$(git remote get-url origin 2> /dev/null)
  if [ -n "$remote" ]; then
    repo_https=${remote/git@github.com:/https:\/\/github.com\/}
    repo_https=${repo_https%.git}
    repo_name=$(basename "$repo_https")
  fi

  stash=$(git stash list 2> /dev/null | grep -c .)
fi

# Autocompact threshold (env override, else 80).
ac=80
case "$CLAUDE_AUTOCOMPACT_PCT_OVERRIDE" in
  '' | *[!0-9]*) : ;;
  *) if [ "$CLAUDE_AUTOCOMPACT_PCT_OVERRIDE" -ge 1 ] && [ "$CLAUDE_AUTOCOMPACT_PCT_OVERRIDE" -le 100 ]; then
    ac=$CLAUDE_AUTOCOMPACT_PCT_OVERRIDE
  fi ;;
esac

# CWD: prefer project_dir when in a worktree.
if [ -n "$worktree_name_input" ] && [ -n "$project_dir" ]; then
  cwd=$project_dir
elif [ -n "$cwd_input" ]; then
  cwd=$cwd_input
else
  cwd=$(pwd)
fi
dir_disp=$(dir_display "$cwd")

# ── Line 1 ──────────────────────────────────────────────────────────────────
if [ -n "$repo_name" ]; then
  id_part="${BOLD}${NEAR_WHITE}$(osc8 "$repo_https" "$repo_name")${RST}"
else
  id_part="${BOLD}${NEAR_WHITE}${dir_disp}${RST}"
fi
line1=$id_part

if [ "$git_is_repo" -eq 1 ] || [ -n "$branch" ]; then
  b=$branch
  [ -z "$b" ] && b="-"
  if [ -n "$repo_https" ] && [ -n "$branch" ]; then
    b_disp=$(osc8 "$repo_https/tree/$branch" "$b")
  else
    b_disp=$b
  fi
  line1="${line1} ${MUTED}[${RST}${BLUE}${GLYPH_BRANCH} ${b_disp}${MUTED}]${RST}"
fi

wt=$worktree_name_input
[ -z "$wt" ] && wt=$git_worktree_name
if [ -n "$wt" ]; then
  line1="${line1} ${MUTED}[${RST}${MAGENTA}${GLYPH_WORKTREE} ${wt}${MUTED}]${RST}"
fi

if [ -n "$pr_number" ]; then
  if [ -n "$repo_https" ]; then
    pr_id=$(osc8 "$repo_https/pull/$pr_number" "${GLYPH_PR} #${pr_number}")
  else
    pr_id="${GLYPH_PR} #${pr_number}"
  fi
  if [ -z "$pr_state" ]; then
    line1="${line1} ${MUTED}[${RST}${CYAN}${pr_id}${MUTED}]${RST}"
  else
    pc=$(pr_state_color "$pr_state")
    line1="${line1} ${MUTED}[${RST}${CYAN}${pr_id}: ${pc}${pr_state}${MUTED}]${RST}"
  fi
fi

# Counters (stash, conflict, untracked, modified, staged, ahead, behind).
counters=""
add_counter() { [ -z "$counters" ] && counters=$1 || counters="${counters}${MUTED}, ${RST}$1"; }
plur() { [ "$1" -eq 1 ] && printf '%s' "$2" || printf '%s' "$3"; }

[ "$stash" -gt 0 ] && add_counter "${MAGENTA}${stash} $(plur "$stash" stash stashes)${RST}"
[ "$conflict" -gt 0 ] && add_counter "${BOLD}${RED}${conflict} $(plur "$conflict" conflict conflicts)${RST}"
[ "$untracked" -gt 0 ] && add_counter "${CYAN}${untracked} untracked${RST}"
[ "$unstaged" -gt 0 ] && add_counter "${YELLOW}${unstaged} modified${RST}"
[ "$staged" -gt 0 ] && add_counter "${GREEN}${staged} staged${RST}"
[ "$ahead" -gt 0 ] && add_counter "${GREEN}${ahead} ahead${RST}"
[ "$behind" -gt 0 ] && add_counter "${RED}${behind} behind${RST}"
[ -n "$counters" ] && line1="${line1} ${MUTED}[C: ${RST}${counters}${MUTED}]${RST}"

if [ "$lines_added" -gt 0 ] || [ "$lines_removed" -gt 0 ]; then
  line1="${line1} ${MUTED}[${RST}${GREEN}+${lines_added}${MUTED}/${RST}${RED}-${lines_removed}${MUTED}]${RST}"
fi
printf '%s\n' "$line1"

# ── Line 2 ──────────────────────────────────────────────────────────────────
line2=""
[ -n "$model_name" ] && line2="${MUTED}[${RST}${CYAN}M: ${model_name}${MUTED}]${RST}"
if [ -n "$effort_level" ]; then
  [ -n "$line2" ] && line2="${line2} "
  line2="${line2}${MUTED}[${RST}${CYAN}E: ${effort_level}${MUTED}]${RST}"
fi
[ -n "$line2" ] && printf '%s\n' "$line2"

# ── Line 3: CTX bar ─────────────────────────────────────────────────────────
used_int=$(int_prefix "$used_pct")
ctx_bar=$(render_bar "$used_int" "$ac" "" "$cols" "$AUTOCOMPACT")
ctx_warn=""
[ "$used_int" -ge "$ac" ] && ctx_warn=" ${AUTOCOMPACT}AC${RST}"
[ -n "$exceeds_200k" ] && ctx_warn="${ctx_warn} ${BOLD}${RED}200k+${RST}"
printf -v ctx_lbl '%-3s' "CTX"
printf -v ctx_pct '%3s' "$used_int"
printf '%s%s%s %s %s%s%%%s%s\n' "$MUTED" "$ctx_lbl" "$RST" "$ctx_bar" "$MUTED" "$ctx_pct" "$RST" "$ctx_warn"

# ── Lines 4-5: rate-limit windows ───────────────────────────────────────────
print_window() {
  local pct_str=$1 resets_str=$2 window_min=$3 label=$4
  if [ -z "$pct_str" ] || [ -z "$resets_str" ]; then
    if [ "$label" = "5h" ]; then
      printf -v lbl '%-3s' "$label"
      printf '%s%s%s %s[ rate_limits unavailable %s make a request to populate ]%s\n' \
        "$MUTED" "$lbl" "$RST" "$MUTED" "$EMDASH" "$RST"
    fi
    return
  fi
  local pct
  pct=$(int_prefix "$pct_str")
  local resets=$resets_str
  case "$resets" in *[!0-9]*) resets=0 ;; esac
  local now
  now=$(date +%s)
  local remain_sec=$((resets > now ? resets - now : 0))
  local remain_min=$((remain_sec / 60))
  [ "$remain_min" -gt "$window_min" ] && remain_min=$window_min
  local clock_pct=$(((window_min - remain_min) * 100 / window_min))
  local proj_pct=""
  [ "$clock_pct" -gt 5 ] && proj_pct=$((pct * 100 / clock_pct))
  local delta=$((pct - clock_pct)) delta_str
  if [ "$delta" -gt 0 ]; then
    delta_str="${RED}+${delta}%${RST}"
  elif [ "$delta" -lt 0 ]; then
    delta_str="${GREEN}${delta}%${RST}"
  else delta_str="${MUTED}0%${RST}"; fi

  local time_label
  if [ "$remain_min" -ge 1440 ]; then
    printf -v time_label '%dd %02dh left' "$((remain_min / 1440))" "$(((remain_min % 1440) / 60))"
  elif [ "$remain_min" -ge 60 ]; then
    printf -v time_label '%dh %02dm left' "$((remain_min / 60))" "$((remain_min % 60))"
  else
    printf -v time_label '%dm left' "$remain_min"
  fi

  local bar
  bar=$(render_bar "$pct" "$clock_pct" "$proj_pct" "$cols" "$MARKER")
  printf -v lbl '%-3s' "$label"
  printf -v pctf '%3s' "$pct"
  printf '%s%s%s %s %s%s%%%s [%s%s%s] [%s%s]%s\n' \
    "$MUTED" "$lbl" "$RST" "$bar" "$MUTED" "$pctf" "$RST" \
    "$MARKER" "$time_label" "$MUTED" "$delta_str" "$MUTED" "$RST"
}
print_window "$five_pct" "$five_resets_at" 300 "5h"
print_window "$seven_pct" "$seven_resets_at" 10080 "7d"

# ── Line 6: cost ────────────────────────────────────────────────────────────
cost_display=$(awk -v c="$cost_usd" 'BEGIN{ if (c ~ /^[0-9]+(\.[0-9]+)?$/) printf "$%.2f", c }')
if [ -n "$cost_display" ]; then
  money=$cost_display
  burn=$(awk -v c="$cost_usd" -v d="$duration_ms" 'BEGIN{
    if (c ~ /^[0-9]+(\.[0-9]+)?$/ && c+0 > 0 && d+0 >= 60000)
      printf "$%.2f/h", (c+0) / ((d+0)/3600000.0) }')
  [ -n "$burn" ] && money="${money} (${burn})"
  printf '%s[%s%s%s%s]%s\n' "$MUTED" "$RST" "$GREEN" "$money" "$MUTED" "$RST"
fi
