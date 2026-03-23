#!/bin/sh
# git-data.sh — Single-pass git data cache
# Gathers all git state once and writes key=value pairs to a sourceable cache file.
# Cache file: /tmp/git-data-cache-$(id -u).sh
# Consumers: source the cache file to get all variables.
#
# Variables written:
#   GIT_IS_REPO        — "1" if inside a git work tree, "" otherwise
#   GIT_DIR            — path to .git dir
#   GIT_TOPLEVEL       — repo root path
#   GIT_BRANCH         — current branch or short HEAD hash
#   GIT_REMOTE_URL     — origin remote URL (raw)
#   GIT_REPO_NAME      — repo name (basename, no .git)
#   GIT_REPO_HTTPS     — HTTPS URL (for links)
#   GIT_PORCELAIN      — raw porcelain v1 output (newline-delimited, # header lines stripped)
#   GIT_CONFLICT_COUNT
#   GIT_STAGED_COUNT
#   GIT_UNSTAGED_COUNT
#   GIT_UNTRACKED_COUNT
#   GIT_STASH_COUNT
#   GIT_AHEAD
#   GIT_BEHIND
#   GIT_PR_STATUS      — "none" | "pass" | "pending" | "fail"
#   GIT_PR_URL         — PR URL (empty when no PR)
#   GIT_CACHE_TIME     — unix timestamp when cache was written

_cache_file="/tmp/git-data-cache-$(id -u).sh"

# -- Repo detection ------------------------------------------------------------
GIT_IS_REPO=""
GIT_DIR=""
GIT_TOPLEVEL=""
GIT_BRANCH=""
GIT_REMOTE_URL=""
GIT_REPO_NAME=""
GIT_REPO_HTTPS=""
GIT_PORCELAIN=""
GIT_CONFLICT_COUNT=0
GIT_STAGED_COUNT=0
GIT_UNSTAGED_COUNT=0
GIT_UNTRACKED_COUNT=0
GIT_STASH_COUNT=0
GIT_AHEAD=0
GIT_BEHIND=0
GIT_PR_STATUS="none"
GIT_PR_URL=""

if _revparse=$(git rev-parse --git-dir --show-toplevel 2>/dev/null); then
  GIT_IS_REPO="1"
  GIT_DIR=$(printf '%s' "$_revparse" | sed -n '1p')
  GIT_TOPLEVEL=$(printf '%s' "$_revparse" | sed -n '2p')

  # Single git call: branch name, ahead/behind, and porcelain status
  # --porcelain=v2 header lines start with '#'; file entries do not.
  _status_out=$(git status --porcelain=v2 --branch --ahead-behind 2>/dev/null)

  # Parse header lines for branch and ahead/behind
  GIT_BRANCH=$(printf '%s' "$_status_out" | sed -n 's/^# branch\.head //p')
  [ -z "$GIT_BRANCH" ] || [ "$GIT_BRANCH" = "(detached)" ] && \
    GIT_BRANCH=$(git rev-parse --short HEAD 2>/dev/null)

  _ab=$(printf '%s' "$_status_out" | sed -n 's/^# branch\.ab //p')
  if [ -n "$_ab" ]; then
    GIT_AHEAD=$(printf '%s' "$_ab" | sed 's/^+\([0-9]*\) .*/\1/')
    GIT_BEHIND=$(printf '%s' "$_ab" | sed 's/.*-\([0-9]*\)$/\1/')
  fi

  # Remote URL / repo name / HTTPS URL
  _remote=$(git remote get-url origin 2>/dev/null)
  if [ -n "$_remote" ]; then
    GIT_REMOTE_URL="$_remote"
    GIT_REPO_HTTPS=$(printf '%s' "$_remote" | sed 's|git@github.com:|https://github.com/|' | sed 's|\.git$||')
    GIT_REPO_NAME=$(basename "$GIT_REPO_HTTPS")
  fi

  # Extract v1-compatible porcelain lines (non-header lines from v2 output)
  # v2 format: '1 XY ...' (ordinary), '2 XY ...' (rename), '? path' (untracked), 'u ...' (unmerged)
  # We re-derive v1-style XY codes for compatibility with downstream consumers.
  _porcelain_tmp=$(mktemp)
  printf '%s' "$_status_out" | grep -v '^#' | while IFS= read -r _line; do
    _type=$(printf '%.1s' "$_line")
    case "$_type" in
      1) # ordinary changed entry: '1 XY ...'
        _xy=$(printf '%s' "$_line" | cut -c3-4)
        _path=$(printf '%s' "$_line" | cut -d' ' -f9-)
        printf '%s %s\n' "$_xy" "$_path"
        ;;
      2) # renamed/copied entry: '2 XY ...'
        _xy=$(printf '%s' "$_line" | cut -c3-4)
        _path=$(printf '%s' "$_line" | cut -d' ' -f10-)
        printf '%s %s\n' "$_xy" "$_path"
        ;;
      u) # unmerged entry: 'u XY ...'
        _xy=$(printf '%s' "$_line" | cut -c3-4)
        _path=$(printf '%s' "$_line" | cut -d' ' -f11-)
        printf '%s %s\n' "$_xy" "$_path"
        ;;
      '?') # untracked: '? path'
        _path=$(printf '%s' "$_line" | cut -c3-)
        printf '?? %s\n' "$_path"
        ;;
    esac
  done > "$_porcelain_tmp"
  GIT_PORCELAIN=$(cat "$_porcelain_tmp")
  rm -f "$_porcelain_tmp"

  # Parse porcelain in a single pass
  if [ -n "$GIT_PORCELAIN" ]; then
    while IFS= read -r _line; do
      _x=$(printf '%.1s' "$_line")
      _y=$(printf '%.1s' "${_line#?}")
      case "${_x}${_y}" in
        UU|AA|DD|AU|UA|DU|UD) GIT_CONFLICT_COUNT=$((GIT_CONFLICT_COUNT + 1)) ;;
        '??') GIT_UNTRACKED_COUNT=$((GIT_UNTRACKED_COUNT + 1)) ;;
        *)
          case "$_x" in [MADRC]) GIT_STAGED_COUNT=$((GIT_STAGED_COUNT + 1)) ;; esac
          case "$_y" in [MD]) GIT_UNSTAGED_COUNT=$((GIT_UNSTAGED_COUNT + 1)) ;; esac
          ;;
      esac
    done <<PORCELAIN
$GIT_PORCELAIN
PORCELAIN
  fi

  # Stash count
  _stash_out=$(git stash list 2>/dev/null)
  [ -n "$_stash_out" ] && GIT_STASH_COUNT=$(printf '%s\n' "$_stash_out" | wc -l | tr -d ' ')

  # -- PR cache (async refresh) ------------------------------------------------
  if [ -n "$GIT_REPO_NAME" ] && [ -n "$GIT_BRANCH" ] && command -v gh >/dev/null 2>&1; then
    _pr_cache_dir="/tmp/git-pr-status"
    _repo_id=$(printf '%s' "$GIT_TOPLEVEL" | tr '/' '_')
    _branch_id=$(printf '%s' "$GIT_BRANCH" | tr '/' '_')
    _pr_cache_file="${_pr_cache_dir}/${_repo_id}_${_branch_id}"
    _pr_lock_file="${_pr_cache_file}.lock"
    _now=$(date +%s)
    _ttl=30

    # Always read from cache (stale is fine — async refresh handles freshness)
    if [ -f "$_pr_cache_file" ]; then
      _cached_time=$(sed -n '1p' "$_pr_cache_file")
      GIT_PR_STATUS=$(sed -n '2p' "$_pr_cache_file")
      GIT_PR_URL=$(sed -n '3p' "$_pr_cache_file")
      _age=$(( _now - ${_cached_time:-0} ))
    else
      _age=999
    fi

    # If cache is stale, kick off a background refresh (non-blocking)
    if [ "$_age" -ge "$_ttl" ] && ! [ -f "$_pr_lock_file" ]; then
      mkdir -p "$_pr_cache_dir"
      (
        printf '%s' "$_now" > "$_pr_lock_file"
        _new_status=$(gh pr checks --json state --jq '
          if length == 0 then "none"
          elif all(.state == "SUCCESS") then "pass"
          elif any(.state == "FAILURE" or .state == "CANCELLED") then "fail"
          else "pending"
          end
        ' 2>/dev/null || echo "none")
        _new_url=""
        [ "$_new_status" != "none" ] && _new_url=$(gh pr view --json url --jq .url 2>/dev/null || echo "")
        printf '%s\n%s\n%s' "$(date +%s)" "$_new_status" "$_new_url" > "$_pr_cache_file"
        rm -f "$_pr_lock_file"
      ) &
    fi
  fi
fi

# -- Write cache ---------------------------------------------------------------
GIT_CACHE_TIME=$(date +%s)

# Escape GIT_PORCELAIN for safe single-quoted assignment
# Replace each ' with '\'' so the single-quote wrapping stays valid
_porcelain_escaped=$(printf '%s' "$GIT_PORCELAIN" | sed "s/'/'\\\\''/g")

cat > "$_cache_file" <<CACHE
# git-data cache — generated by git-data.sh
# Generated: $(date)
GIT_CACHE_TIME='${GIT_CACHE_TIME}'
GIT_IS_REPO='${GIT_IS_REPO}'
GIT_DIR='${GIT_DIR}'
GIT_TOPLEVEL='${GIT_TOPLEVEL}'
GIT_BRANCH='${GIT_BRANCH}'
GIT_REMOTE_URL='${GIT_REMOTE_URL}'
GIT_REPO_NAME='${GIT_REPO_NAME}'
GIT_REPO_HTTPS='${GIT_REPO_HTTPS}'
GIT_PORCELAIN='${_porcelain_escaped}'
GIT_CONFLICT_COUNT='${GIT_CONFLICT_COUNT}'
GIT_STAGED_COUNT='${GIT_STAGED_COUNT}'
GIT_UNSTAGED_COUNT='${GIT_UNSTAGED_COUNT}'
GIT_UNTRACKED_COUNT='${GIT_UNTRACKED_COUNT}'
GIT_STASH_COUNT='${GIT_STASH_COUNT}'
GIT_AHEAD='${GIT_AHEAD}'
GIT_BEHIND='${GIT_BEHIND}'
GIT_PR_STATUS='${GIT_PR_STATUS}'
GIT_PR_URL='${GIT_PR_URL}'
CACHE
