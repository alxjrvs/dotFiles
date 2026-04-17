#!/usr/bin/env bash
# UserPromptSubmit hook: inject one-line git context from cache.
# Reads the git-data cache (also used by prompt/statusline) and emits a
# concise summary so Claude doesn't need to call `git status`/`git log`
# for routine state checks. Always exits 0; non-repo directories skip silently.

set -uo pipefail

cache="/tmp/git-data-cache-$(id -u).sh"
age_max=60

# Kick off a background refresh if the cache is stale or missing.
# The output reflects whatever was there at read-time; staleness is acceptable
# for a UserPromptSubmit signal (next turn will have fresh data).
if [[ ! -f "$cache" ]] || [[ $(($(date +%s) - $(stat -f %m "$cache" 2>/dev/null || echo 0))) -gt $age_max ]]; then
  (sh "$HOME/dotFiles/scripts/git-data.sh" >/dev/null 2>&1 &) 2>/dev/null || true
fi

[[ -f "$cache" ]] || exit 0
# shellcheck disable=SC1090
. "$cache" 2>/dev/null || exit 0

[[ "${GIT_IS_REPO:-}" != "1" ]] && exit 0

parts=("branch=$GIT_BRANCH")
total=$((GIT_STAGED_COUNT + GIT_UNSTAGED_COUNT + GIT_UNTRACKED_COUNT))
[[ $total -gt 0 ]] && parts+=("$total uncommitted")
[[ ${GIT_AHEAD:-0} -gt 0 ]] && parts+=("$GIT_AHEAD ahead")
[[ ${GIT_BEHIND:-0} -gt 0 ]] && parts+=("$GIT_BEHIND behind")
[[ ${GIT_CONFLICT_COUNT:-0} -gt 0 ]] && parts+=("$GIT_CONFLICT_COUNT CONFLICTS")
[[ "${GIT_PR_STATUS:-none}" != "none" ]] && parts+=("PR-checks=$GIT_PR_STATUS")

IFS=','
echo "git: ${parts[*]}"
exit 0
