#!/usr/bin/env bash
# UserPromptSubmit hook: record turn-start + inject git-state only when non-trivial.
# - Writes /tmp/claude-turn-start-<session> so notify.sh can gate short Stop events.
# - Emits git-line only when there's something actionable (non-default branch,
#   uncommitted, ahead/behind, conflicts, PR status). Silent on clean default.
# Session burn % lives in the statusline; not injected here.
# Always exits 0.

set -uo pipefail

input=$(cat 2>/dev/null || true)
session_id=$(echo "$input" | jq -r '.session_id // empty' 2>/dev/null)

# Record turn start for the Stop hook duration gate
if [[ -n "$session_id" ]]; then
  date +%s > "/tmp/claude-turn-start-${session_id}" 2>/dev/null || true
fi

_git_key=$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)
_git_hash=$(printf '%s' "$_git_key" | shasum -a 256 | cut -c1-12)
git_cache="/tmp/git-data-cache-$(id -u)-${_git_hash}.sh"
age_max=60

# Kick off a background git refresh if stale (next turn gets fresh data)
if [[ ! -f "$git_cache" ]] || [[ $(($(date +%s) - $(stat -f %m "$git_cache" 2>/dev/null || echo 0))) -gt $age_max ]]; then
  (sh "$HOME/dotFiles/scripts/git-data.sh" >/dev/null 2>&1 &) 2>/dev/null || true
fi

# --- git line (only when non-trivial) ---
[[ ! -f "$git_cache" ]] && exit 0

# shellcheck disable=SC1090
. "$git_cache" 2>/dev/null || true

[[ "${GIT_IS_REPO:-}" != "1" ]] && exit 0

uncommitted=$((${GIT_STAGED_COUNT:-0} + ${GIT_UNSTAGED_COUNT:-0} + ${GIT_UNTRACKED_COUNT:-0}))
ahead=${GIT_AHEAD:-0}
behind=${GIT_BEHIND:-0}
conflicts=${GIT_CONFLICT_COUNT:-0}
pr_status=${GIT_PR_STATUS:-none}
branch=${GIT_BRANCH:-}

# Silent on green: on default branch with nothing notable, emit nothing.
is_default_branch=0
case "$branch" in
  main|master|develop|trunk) is_default_branch=1 ;;
esac

if [[ $is_default_branch -eq 1 && $uncommitted -eq 0 && $ahead -eq 0 && $behind -eq 0 && $conflicts -eq 0 && "$pr_status" == "none" ]]; then
  exit 0
fi

parts=("branch=$branch")
[[ $uncommitted -gt 0 ]] && parts+=("$uncommitted uncommitted")
[[ $ahead -gt 0 ]] && parts+=("$ahead ahead")
[[ $behind -gt 0 ]] && parts+=("$behind behind")
[[ $conflicts -gt 0 ]] && parts+=("$conflicts CONFLICTS")
[[ "$pr_status" != "none" ]] && parts+=("PR-checks=$pr_status")

IFS=','
echo "git: ${parts[*]}"
unset IFS

exit 0
