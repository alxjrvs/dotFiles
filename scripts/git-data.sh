#!/bin/sh
# git-data.sh — Single-pass git data cache
# Gathers all git state once and writes key=value pairs to a sourceable cache file.
# Cache file: $HOME/.cache/git-data/<repo-hash>.sh  (file 600, dir 700)
# Consumers: source the cache file to get all variables.
#
# Variables written:
#   GIT_IS_REPO        — "1" if inside a git work tree, "" otherwise
#   GIT_IS_WORKTREE    — "1" if inside a linked worktree, "" otherwise
#   GIT_WORKTREE_NAME  — basename of the worktree's toplevel dir (empty outside a linked worktree)
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
#   GIT_CACHE_TIME     — unix timestamp when cache was written

# Key cache by repo toplevel (or cwd if not in a repo) so concurrent sessions
# in different projects don't clobber each other's state.
_git_key=$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)
_git_hash=$(printf '%s' "$_git_key" | shasum -a 256 | cut -c1-12)
_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/git-data"
_cache_file="$_cache_dir/${_git_hash}.sh"

# -- Repo detection ------------------------------------------------------------
GIT_IS_REPO=""
GIT_IS_WORKTREE=""
GIT_WORKTREE_NAME=""
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

if _revparse=$(git rev-parse --git-dir --git-common-dir --show-toplevel 2>/dev/null); then
  GIT_IS_REPO="1"
  GIT_DIR=$(printf '%s' "$_revparse" | sed -n '1p')
  _git_common_dir=$(printf '%s' "$_revparse" | sed -n '2p')
  GIT_TOPLEVEL=$(printf '%s' "$_revparse" | sed -n '3p')

  # Linked worktree: --git-dir diverges from --git-common-dir
  if [ "$GIT_DIR" != "$_git_common_dir" ]; then
    GIT_IS_WORKTREE="1"
    GIT_WORKTREE_NAME=$(basename "$GIT_TOPLEVEL")
  fi

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

  # Extract v1-compatible porcelain lines (non-header lines from v2 output).
  # v2 row prefixes: 1=ordinary, 2=rename/copy, u=unmerged, ?=untracked.
  # Using if/elif instead of case here because bash 3.2 (macOS /bin/sh)
  # mis-parses case statements inside nested command substitutions.
  GIT_PORCELAIN=$(printf '%s' "$_status_out" | grep -v '^#' | while IFS= read -r _line; do
    _type=$(printf '%.1s' "$_line")
    if [ "$_type" = "1" ]; then
      _xy=$(printf '%s' "$_line" | cut -c3-4)
      _path=$(printf '%s' "$_line" | cut -d' ' -f9-)
      printf '%s %s\n' "$_xy" "$_path"
    elif [ "$_type" = "2" ]; then
      _xy=$(printf '%s' "$_line" | cut -c3-4)
      _path=$(printf '%s' "$_line" | cut -d' ' -f10-)
      printf '%s %s\n' "$_xy" "$_path"
    elif [ "$_type" = "u" ]; then
      _xy=$(printf '%s' "$_line" | cut -c3-4)
      _path=$(printf '%s' "$_line" | cut -d' ' -f11-)
      printf '%s %s\n' "$_xy" "$_path"
    elif [ "$_type" = "?" ]; then
      _path=$(printf '%s' "$_line" | cut -c3-)
      printf '?? %s\n' "$_path"
    fi
  done)

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

fi

# -- Write cache (atomic, user-private) ----------------------------------------
GIT_CACHE_TIME=$(date +%s)

# Escape every string field for safe single-quoted assignment. Without this, a
# crafted branch name or repo path could break out of the single-quote wrapping
# and execute when consumers source the cache. Done OUTSIDE the heredoc because
# bash 3.2 (macOS /bin/sh) mis-parses $(...) containing double-quoted args
# inside an unquoted heredoc.
_sq_escape() {
  printf '%s' "$1" | sed "s/'/'\\\\''/g"
}
_e_worktree_name=$(_sq_escape "$GIT_WORKTREE_NAME")
_e_dir=$(_sq_escape "$GIT_DIR")
_e_toplevel=$(_sq_escape "$GIT_TOPLEVEL")
_e_branch=$(_sq_escape "$GIT_BRANCH")
_e_remote_url=$(_sq_escape "$GIT_REMOTE_URL")
_e_repo_name=$(_sq_escape "$GIT_REPO_NAME")
_e_repo_https=$(_sq_escape "$GIT_REPO_HTTPS")
_e_porcelain=$(_sq_escape "$GIT_PORCELAIN")

# Ensure cache dir exists and is user-private. Mode 700 protects against any
# future config that puts other users in the same group on shared boxes.
mkdir -p "$_cache_dir" 2>/dev/null && chmod 700 "$_cache_dir" 2>/dev/null

# Write to a tempfile in the same dir, then atomic rename so consumers never
# source a partial write. umask 077 makes the new file mode 600.
_cache_tmp="${_cache_file}.$$.tmp"
(
  umask 077
  cat > "$_cache_tmp" <<CACHE
# git-data cache — generated by git-data.sh
# Generated: $(date)
GIT_CACHE_TIME='${GIT_CACHE_TIME}'
GIT_IS_REPO='${GIT_IS_REPO}'
GIT_IS_WORKTREE='${GIT_IS_WORKTREE}'
GIT_WORKTREE_NAME='${_e_worktree_name}'
GIT_DIR='${_e_dir}'
GIT_TOPLEVEL='${_e_toplevel}'
GIT_BRANCH='${_e_branch}'
GIT_REMOTE_URL='${_e_remote_url}'
GIT_REPO_NAME='${_e_repo_name}'
GIT_REPO_HTTPS='${_e_repo_https}'
GIT_PORCELAIN='${_e_porcelain}'
GIT_CONFLICT_COUNT='${GIT_CONFLICT_COUNT}'
GIT_STAGED_COUNT='${GIT_STAGED_COUNT}'
GIT_UNSTAGED_COUNT='${GIT_UNSTAGED_COUNT}'
GIT_UNTRACKED_COUNT='${GIT_UNTRACKED_COUNT}'
GIT_STASH_COUNT='${GIT_STASH_COUNT}'
GIT_AHEAD='${GIT_AHEAD}'
GIT_BEHIND='${GIT_BEHIND}'
CACHE
) && mv -f "$_cache_tmp" "$_cache_file" || rm -f "$_cache_tmp"
