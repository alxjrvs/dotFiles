#!/usr/bin/env bash
# Claude Code status line - plain-ASCII layout with colored git values:
#   Line 1: repo/dir  branch  [wt:name]  [counters]
#   Line 2: [M: model]  [A: advisor]  [E: effort]
#   Line 3: Ctx [bar] N%
#   Line 4: 5h  [bar] N%  [time left]  [delta]
#   Line 5: 7d  [bar] N%  [time left]  [delta]

input=$(cat)

# -- Git data cache ------------------------------------------------------------
bash "$HOME/dotFiles/scripts/git-data.sh"
_git_key=$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)
_git_hash=$(printf '%s' "$_git_key" | shasum -a 256 | cut -c1-12)
_git_cache="${XDG_CACHE_HOME:-$HOME/.cache}/git-data/${_git_hash}.sh"
# shellcheck disable=SC1090
[ -f "$_git_cache" ] && . "$_git_cache"

# -- Parse JSON input ----------------------------------------------------------
# rate_limits.* are first-party Claude.ai subscription windows (Pro/Max). They
# appear only AFTER the first API response in the session, so handle absence
# gracefully. resets_at is unix epoch seconds.
eval "$(echo "$input" | jq -r '
  @sh "used_pct=\(.context_window.used_percentage // "")",
  @sh "duration_ms=\(.cost.total_duration_ms // 0)",
  @sh "worktree_name=\(.worktree.name // "")",
  @sh "project_dir=\(.workspace.project_dir // "")",
  @sh "cwd=\(.workspace.current_dir // "")",
  @sh "model_name=\(.model.display_name // "")",
  @sh "effort_level=\(.effort.level // "")",
  @sh "five_pct=\(.rate_limits.five_hour.used_percentage // "")",
  @sh "five_resets_at=\(.rate_limits.five_hour.resets_at // "")",
  @sh "seven_pct=\(.rate_limits.seven_day.used_percentage // "")",
  @sh "seven_resets_at=\(.rate_limits.seven_day.resets_at // "")"
' | tr ',' '\n')"

_settings="$HOME/.claude/settings.json"
advisor_name=""
if [ -f "$_settings" ]; then
  advisor_name=$(jq -r '.advisorModel // ""' "$_settings" 2>/dev/null)
fi

# -- Directory -----------------------------------------------------------------
[ -n "$worktree_name" ] && [ -n "$project_dir" ] && cwd="$project_dir"
[ -z "$cwd" ] && cwd=$(pwd)
_home="${HOME:-$(eval echo ~)}"
_home="${_home%/}"
[ -z "$_home" ] && _home="/Users/$(id -un)"
case "$cwd" in
  "$_home"*) home_rel="~${cwd#"$_home"}" ;;
  *) home_rel="$cwd" ;;
esac
IFS='/' read -ra _parts <<< "$home_rel"
_n=${#_parts[@]}
if [ "$_n" -le 2 ]; then
  dir_display="$home_rel"
else
  dir_display="${_parts[$(( _n - 2 ))]}/${_parts[$(( _n - 1 ))]}"
fi

# -- Cache values --------------------------------------------------------------
repo_url="${GIT_REPO_HTTPS:-}"
repo_name="${GIT_REPO_NAME:-}"
branch="${GIT_BRANCH:-}"

export STATUSLINE_WORKTREE="$worktree_name"

# -- Styling -------------------------------------------------------------------
DIM=$'\e[2m'
UNDIM=$'\e[22m'
BOLD=$'\e[1m'
RESET=$'\e[0m'
MUTED=$'\e[90m'   # bright black — matches Claude TUI secondary text
RED=$'\e[31m'
GREEN=$'\e[32m'
YELLOW=$'\e[33m'
BLUE=$'\e[34m'
MAGENTA=$'\e[35m'
CYAN=$'\e[36m'
MARKER=$'\e[38;2;96;200;255m'   # bright cyan — clock-time marker (distinct from burn gradient)
PROJ=$'\e[38;2;255;210;80m'     # amber — projected end-of-block burn marker

# -- Gradient: neutral -> warm -> white hot (blackbody-style) ------------------
# Anchors (R G B):
#   0%:  74 79 92     cool neutral grey
#   35%: 176 74 58    dull warm red
#   70%: 240 160 64   orange / amber
#   90%: 255 232 144  hot yellow
#   100%: 255 255 255 white hot
PIP_COUNT=30
PIP_FILL=$'▰'   # ▰  filled pip — matches Claude's progress bar
PIP_EMPTY=$'▱'  # ▱  empty pip

_grad_at() {
  local t="$1" r g b u
  if [ "$t" -le 3500 ]; then
    u=$(( t * 10000 / 3500 ))
    r=$(( 74 + (176 - 74) * u / 10000 ))
    g=$(( 79 + (74 - 79) * u / 10000 ))
    b=$(( 92 + (58 - 92) * u / 10000 ))
  elif [ "$t" -le 7000 ]; then
    u=$(( (t - 3500) * 10000 / 3500 ))
    r=$(( 176 + (240 - 176) * u / 10000 ))
    g=$(( 74 + (160 - 74) * u / 10000 ))
    b=$(( 58 + (64 - 58) * u / 10000 ))
  elif [ "$t" -le 9000 ]; then
    u=$(( (t - 7000) * 10000 / 2000 ))
    r=$(( 240 + (255 - 240) * u / 10000 ))
    g=$(( 160 + (232 - 160) * u / 10000 ))
    b=$(( 64 + (144 - 64) * u / 10000 ))
  else
    u=$(( (t - 9000) * 10000 / 1000 ))
    r=255
    g=$(( 232 + (255 - 232) * u / 10000 ))
    b=$(( 144 + (255 - 144) * u / 10000 ))
  fi
  printf '%d;%d;%d' "$r" "$g" "$b"
}

declare -a PIPS
for ((k=0; k<PIP_COUNT; k++)); do
  PIPS[$k]=$(_grad_at "$(( k * 10000 / (PIP_COUNT - 1) ))")
done

render_bar() {
  local pct="$1"
  local marker_pct="$2"
  local proj_pct="$3"
  [ -z "$pct" ] && pct=0
  local filled=$(( pct * PIP_COUNT / 100 ))
  [ "$filled" -gt "$PIP_COUNT" ] && filled="$PIP_COUNT"
  [ "$pct" -gt 0 ] && [ "$filled" -eq 0 ] && filled=1

  local marker_idx=-1 marker_expired=0
  if [ -n "$marker_pct" ]; then
    if [ "$marker_pct" -ge 100 ]; then
      marker_idx=$(( PIP_COUNT - 1 )); marker_expired=1
    else
      marker_idx=$(( marker_pct * PIP_COUNT / 100 ))
      [ "$marker_idx" -lt 0 ] && marker_idx=0
    fi
  fi

  local proj_idx=-1
  if [ -n "$proj_pct" ] && [ "$proj_pct" -le 100 ]; then
    proj_idx=$(( proj_pct * PIP_COUNT / 100 ))
    [ "$proj_idx" -ge "$PIP_COUNT" ] && proj_idx=$(( PIP_COUNT - 1 ))
    [ "$proj_idx" -lt 0 ] && proj_idx=0
  fi

  local out=""
  local i=0 pip
  while [ "$i" -lt "$PIP_COUNT" ]; do
    if [ "$i" -lt "$filled" ]; then pip="$PIP_FILL"; else pip="$PIP_EMPTY"; fi
    if [ "$i" -eq "$marker_idx" ]; then
      if [ "$marker_expired" -eq 1 ]; then
        out="${out}${UNDIM}${RED}${pip}"
      else
        out="${out}${UNDIM}${MARKER}${pip}"
      fi
    elif [ "$i" -eq "$proj_idx" ]; then
      out="${out}${UNDIM}${PROJ}${pip}"
    elif [ "$i" -lt "$filled" ]; then
      out="${out}${UNDIM}"$'\e[38;2;'"${PIPS[$i]}"$'m'"${pip}"
    else
      out="${out}${MUTED}${pip}"
    fi
    i=$(( i + 1 ))
  done
  out="${out}${RESET}"
  printf '%s' "$out"
}

# == Line 1: Identity + git ===================================================
NEAR_WHITE=$'\e[38;2;235;235;235m'
if [ -n "$repo_name" ]; then
  id_part=$'\e]8;;'"${repo_url}"$'\a'"${BOLD}${NEAR_WHITE}${repo_name}${RESET}"$'\e]8;;\a'
else
  id_part="${BOLD}${NEAR_WHITE}${dir_display}${RESET}"
fi

line1="${id_part}"

if [ -n "${GIT_IS_REPO:-}" ] || [ -n "$branch" ]; then
  [ -z "$branch" ] && branch="-"
  line1="${line1} ${MUTED}[${RESET}${BLUE}${branch}${MUTED}]${RESET}"
fi

[ -z "$worktree_name" ] && worktree_name="${GIT_WORKTREE_NAME:-}"
[ -n "$worktree_name" ] && line1="${line1} ${MUTED}[${RESET}${MAGENTA}${worktree_name}${MUTED}]${RESET}"

_pl() { [ "$1" -eq 1 ] && printf '%s' "$2" || printf '%s' "$3"; }

counters=""
_sep="${MUTED}, ${RESET}"
_push() { [ -z "$counters" ] && counters="$1" || counters="${counters}${_sep}${1}"; }

[ "${GIT_STASH_COUNT:-0}" -gt 0 ]     && _push "${MAGENTA}${GIT_STASH_COUNT} $(_pl "${GIT_STASH_COUNT}" stash stashes)${RESET}"
[ "${GIT_CONFLICT_COUNT:-0}" -gt 0 ]  && _push "${BOLD}${RED}${GIT_CONFLICT_COUNT} $(_pl "${GIT_CONFLICT_COUNT}" conflict conflicts)${RESET}"
[ "${GIT_UNTRACKED_COUNT:-0}" -gt 0 ] && _push "${CYAN}${GIT_UNTRACKED_COUNT} untracked${RESET}"
[ "${GIT_UNSTAGED_COUNT:-0}" -gt 0 ]  && _push "${YELLOW}${GIT_UNSTAGED_COUNT} modified${RESET}"
[ "${GIT_STAGED_COUNT:-0}" -gt 0 ]    && _push "${GREEN}${GIT_STAGED_COUNT} staged${RESET}"
[ "${GIT_AHEAD:-0}" -gt 0 ]           && _push "${GREEN}${GIT_AHEAD} ahead${RESET}"
[ "${GIT_BEHIND:-0}" -gt 0 ]          && _push "${RED}${GIT_BEHIND} behind${RESET}"
[ -n "$counters" ] && line1="${line1} ${MUTED}[${RESET}${counters}${MUTED}]${RESET}"

printf '%s\n' "$line1"

# == Line 2: Model + advisor ==================================================
model_part=""
[ -n "$model_name" ]    && model_part="${model_part}${MUTED}[${RESET}${CYAN}M: ${model_name}${MUTED}]${RESET}"
[ -n "$advisor_name" ]  && model_part="${model_part} ${MUTED}[${RESET}${CYAN}A: ${advisor_name}${MUTED}]${RESET}"
[ -n "$effort_level" ]  && model_part="${model_part} ${MUTED}[${RESET}${CYAN}E: ${effort_level}${MUTED}]${RESET}"
[ -n "$model_part" ] && printf '%s\n' "$model_part"

# == Line 3: Context bar ======================================================
used_int=0
[ -n "$used_pct" ] && used_int=${used_pct%%.*}
ctx_bar=$(render_bar "$used_int")
printf '%s%-3s%s %s %s%3d%%%s\n' "$MUTED" "Ctx" "$RESET" "$ctx_bar" "$MUTED" "$used_int" "$RESET"

# == Lines 4-5: rate limits (5-hour + 7-day) ==================================
# render_window: pct resets_at window_min label
#   pct          — used percentage (integer)
#   resets_at    — unix epoch seconds when window resets
#   window_min   — total minutes in the window (300 for 5h, 10080 for 7d)
#   label        — left-column label (e.g. "5h", "7d")
render_window() {
  local pct="$1" resets_at="$2" window_min="$3" label="$4"
  local _now remain_sec remain_min clock_pct proj_pct delta delta_str time_label
  _now=$(date +%s)
  remain_sec=$(( resets_at - _now ))
  [ "$remain_sec" -lt 0 ] && remain_sec=0
  remain_min=$(( remain_sec / 60 ))
  [ "$remain_min" -gt "$window_min" ] && remain_min=$window_min

  clock_pct=$(( (window_min - remain_min) * 100 / window_min ))

  # Projection: linear extrapolation. Suppress early — division by small
  # clock_pct produces noise.
  proj_pct=""
  if [ "$clock_pct" -gt 5 ]; then
    proj_pct=$(( pct * 100 / clock_pct ))
  fi

  delta=$(( pct - clock_pct ))
  if [ "$delta" -gt 0 ]; then
    delta_str="${RED}+${delta}%${RESET}"
  elif [ "$delta" -lt 0 ]; then
    delta_str="${GREEN}${delta}%${RESET}"
  else
    delta_str="${MUTED}0%${RESET}"
  fi

  local d h m
  if [ "$remain_min" -ge 1440 ]; then
    d=$(( remain_min / 1440 ))
    h=$(( (remain_min % 1440) / 60 ))
    time_label=$(printf '%dd %02dh left' "$d" "$h")
  elif [ "$remain_min" -ge 60 ]; then
    h=$(( remain_min / 60 ))
    m=$(( remain_min % 60 ))
    time_label=$(printf '%dh %02dm left' "$h" "$m")
  else
    time_label=$(printf '%dm left' "$remain_min")
  fi

  local bar
  bar=$(render_bar "$pct" "$clock_pct" "$proj_pct")
  printf '%s%-3s%s %s %s%3d%%%s [%s%s%s] [%s%s]%s' \
    "$MUTED" "$label" "$RESET" \
    "$bar" \
    "$MUTED" "$pct" "$RESET" \
    "$MARKER" "$time_label" "$MUTED" \
    "$delta_str" "$MUTED" \
    "$RESET"
}

if [ -n "$five_pct" ] && [ -n "$five_resets_at" ]; then
  render_window "${five_pct%%.*}" "$five_resets_at" 300 "5h"
  printf '\n'
else
  printf '%s%-3s%s %s[ rate_limits unavailable — make a request to populate ]%s\n' \
    "$MUTED" "5h" "$RESET" "$MUTED" "$RESET"
fi

if [ -n "$seven_pct" ] && [ -n "$seven_resets_at" ]; then
  render_window "${seven_pct%%.*}" "$seven_resets_at" 10080 "7d"
fi
