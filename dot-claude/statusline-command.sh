#!/usr/bin/env bash
# Claude Code status line - plain-ASCII layout with colored git values:
#   Line 1: repo/dir  branch  [wt:name]  [counters]  [PR:status]
#   Line 2: context [bar] N%
#   Line 3: session [bar] N%

input=$(cat)

# -- Git data cache ------------------------------------------------------------
bash "$HOME/dotFiles/scripts/git-data.sh"
_git_key=$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)
_git_hash=$(printf '%s' "$_git_key" | shasum -a 256 | cut -c1-12)
# shellcheck disable=SC1090
. "/tmp/git-data-cache-$(id -u)-${_git_hash}.sh"

# -- Session window cache (async via ccusage) ----------------------------------
sh "$HOME/dotFiles/scripts/session-data.sh"
_session_cache="/tmp/session-data-cache-$(id -u).sh"
# shellcheck disable=SC1090
[ -f "$_session_cache" ] && . "$_session_cache"

# -- Parse JSON input ----------------------------------------------------------
eval "$(echo "$input" | jq -r '
  @sh "used_pct=\(.context_window.used_percentage // "")",
  @sh "duration_ms=\(.cost.total_duration_ms // 0)",
  @sh "worktree_name=\(.worktree.name // "")",
  @sh "project_dir=\(.workspace.project_dir // "")",
  @sh "cwd=\(.workspace.current_dir // "")"
' | tr ',' '\n')"

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
pr_status="${GIT_PR_STATUS:-none}"
pr_url="${GIT_PR_URL:-}"
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

  local out="${MUTED}[${RESET}"
  local i=0
  while [ "$i" -lt "$PIP_COUNT" ]; do
    if [ "$i" -eq "$marker_idx" ]; then
      if [ "$marker_expired" -eq 1 ]; then
        out="${out}${UNDIM}${MARKER}X"
      else
        out="${out}${UNDIM}${MARKER}|"
      fi
    elif [ "$i" -eq "$proj_idx" ]; then
      out="${out}${UNDIM}${PROJ}*"
    elif [ "$i" -lt "$filled" ]; then
      out="${out}${UNDIM}"$'\e[38;2;'"${PIPS[$i]}"$'m#'
    else
      out="${out}${DIM}-"
    fi
    i=$(( i + 1 ))
  done
  out="${out}${RESET}${MUTED}]${RESET}"
  printf '%s' "$out"
}

# == Line 1: Identity + git ===================================================
# Repo name stays a consistent near-white; CI state is conveyed by the pill to its right
NEAR_WHITE=$'\e[38;2;235;235;235m'
if [ -n "$repo_name" ]; then
  id_link="$repo_url"
  [ -n "$pr_url" ] && id_link="$pr_url"
  id_part=$'\e]8;;'"${id_link}"$'\a'"${BOLD}${NEAR_WHITE}${repo_name}${RESET}"$'\e]8;;\a'
else
  id_part="${BOLD}${NEAR_WHITE}${dir_display}${RESET}"
fi

# CI status pill — only when repo is GitHub-backed and has a PR with a resolved status
ci_part=""
if [ -n "$repo_name" ]; then
  case "$pr_status" in
    pass)    ci_part=" ${MUTED}[${RESET}${GREEN}ci:pass${MUTED}]${RESET}" ;;
    pending) ci_part=" ${MUTED}[${RESET}${YELLOW}ci:pending${MUTED}]${RESET}" ;;
    fail)    ci_part=" ${MUTED}[${RESET}${RED}ci:fail${MUTED}]${RESET}" ;;
  esac
fi

line1="${id_part}${ci_part}"

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

# == Line 2: Context bar ======================================================
used_int=0
[ -n "$used_pct" ] && used_int=${used_pct%%.*}
ctx_bar=$(render_bar "$used_int")
printf '%scontext%s %s %s[%3d%%]%s\n' "$MUTED" "$RESET" "$ctx_bar" "$MUTED" "$used_int" "$RESET"

# == Line 3: Session — burn % against block token limit; time-left as indicator
_have_ccusage=0
if [ -x "$HOME/.bun/bin/ccusage" ] || command -v ccusage >/dev/null 2>&1; then
  _have_ccusage=1
fi

if [ "$_have_ccusage" -eq 0 ]; then
  printf '%ssession%s %s[ install ccusage for session chart: %sbun add -g ccusage%s %s]%s' \
    "$MUTED" "$RESET" "$MUTED" "$YELLOW" "$RESET" "$MUTED" "$RESET"
else
  sess_int=0
  sess_label=""
  clock_pct=""
  proj_pct=""
  delta_str=""
  if [ -n "${SESSION_START:-}" ]; then
    sess_int="${SESSION_BURN_PCT:-0}"
    [ -z "$sess_int" ] && sess_int=0
    remain_min="${SESSION_REMAINING_MIN%.*}"
    [ -z "$remain_min" ] && remain_min=0
    [ "$remain_min" -lt 0 ] && remain_min=0
    [ "$remain_min" -gt 300 ] && remain_min=300
    clock_pct=$(( (300 - remain_min) * 100 / 300 ))

    # Projection: linear extrapolation of current burn to end of block.
    # Suppress early in block — division by small clock_pct yields noise.
    if [ "$clock_pct" -gt 5 ]; then
      proj_pct=$(( sess_int * 100 / clock_pct ))
    fi

    delta=$(( sess_int - clock_pct ))
    if [ "$delta" -gt 0 ]; then
      delta_str="${RED}+${delta}%${RESET}"
    elif [ "$delta" -lt 0 ]; then
      delta_str="${GREEN}${delta}%${RESET}"
    else
      delta_str="${MUTED}0%${RESET}"
    fi

    rh=$(( remain_min / 60 ))
    rm=$(( remain_min % 60 ))
    if [ "$rh" -gt 0 ]; then
      sess_label=$(printf '%dh %02dm left' "$rh" "$rm")
    else
      sess_label=$(printf '%dm left' "$rm")
    fi
  fi

  if [ -n "$sess_label" ]; then
    sess_bar=$(render_bar "$sess_int" "$clock_pct" "$proj_pct")
    printf '%ssession%s %s %s[%3d%%] [%s%s%s] [%s%s]%s' \
      "$MUTED" "$RESET" \
      "$sess_bar" \
      "$MUTED" "$sess_int" \
      "$MARKER" "$sess_label" "$MUTED" \
      "$delta_str" "$MUTED" \
      "$RESET"
  fi
fi
