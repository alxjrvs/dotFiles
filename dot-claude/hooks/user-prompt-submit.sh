#!/usr/bin/env bash
# UserPromptSubmit hook: inject one-line context from caches + record turn-start.
# - Writes /tmp/claude-turn-start-<session> so notify.sh can gate short Stop events.
# - Emits git-state line (branch, counts, ahead/behind, PR status).
# - Emits session-burn line (ccusage cache: percent used + time remaining).
# Always exits 0; non-repo directories skip the git line.

set -uo pipefail

input=$(cat 2>/dev/null || true)
session_id=$(echo "$input" | jq -r '.session_id // empty' 2>/dev/null)

# Record turn start for the Stop hook duration gate
if [[ -n "$session_id" ]]; then
  date +%s > "/tmp/claude-turn-start-${session_id}" 2>/dev/null || true
fi

git_cache="/tmp/git-data-cache-$(id -u).sh"
session_cache="/tmp/session-data-cache-$(id -u).sh"
age_max=60

# Kick off a background git refresh if stale (next turn gets fresh data)
if [[ ! -f "$git_cache" ]] || [[ $(($(date +%s) - $(stat -f %m "$git_cache" 2>/dev/null || echo 0))) -gt $age_max ]]; then
  (sh "$HOME/dotFiles/scripts/git-data.sh" >/dev/null 2>&1 &) 2>/dev/null || true
fi

# --- git line ---
git_line=""
if [[ -f "$git_cache" ]]; then
  # shellcheck disable=SC1090
  . "$git_cache" 2>/dev/null || true
  if [[ "${GIT_IS_REPO:-}" == "1" ]]; then
    parts=("branch=$GIT_BRANCH")
    total=$((GIT_STAGED_COUNT + GIT_UNSTAGED_COUNT + GIT_UNTRACKED_COUNT))
    [[ $total -gt 0 ]] && parts+=("$total uncommitted")
    [[ ${GIT_AHEAD:-0} -gt 0 ]] && parts+=("$GIT_AHEAD ahead")
    [[ ${GIT_BEHIND:-0} -gt 0 ]] && parts+=("$GIT_BEHIND behind")
    [[ ${GIT_CONFLICT_COUNT:-0} -gt 0 ]] && parts+=("$GIT_CONFLICT_COUNT CONFLICTS")
    [[ "${GIT_PR_STATUS:-none}" != "none" ]] && parts+=("PR-checks=$GIT_PR_STATUS")
    IFS=','
    git_line="git: ${parts[*]}"
    unset IFS
  fi
fi

# --- session line (ccusage cache) ---
session_line=""
if [[ -f "$session_cache" ]]; then
  # shellcheck disable=SC1090
  . "$session_cache" 2>/dev/null || true
  if [[ -n "${SESSION_START:-}" && -n "${SESSION_BURN_PCT:-}" ]]; then
    burn="${SESSION_BURN_PCT%.*}"
    remain_raw="${SESSION_REMAINING_MIN%.*}"
    remain="${remain_raw:-0}"
    [[ "$remain" -lt 0 ]] && remain=0
    rh=$(( remain / 60 ))
    rm_=$(( remain % 60 ))
    if (( rh > 0 )); then
      session_line="session: ${burn}% burn, ${rh}h${rm_}m left"
    else
      session_line="session: ${burn}% burn, ${rm_}m left"
    fi
  fi
fi

[[ -n "$git_line" ]] && echo "$git_line"
[[ -n "$session_line" ]] && echo "$session_line"

exit 0
