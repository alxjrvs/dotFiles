#!/usr/bin/env bash
# Stop hook: run the repo's own commit gate over this turn's uncommitted work before the agent
# may call itself done. Everything else here stops a bad ACTION; this checks the WORK.
#
# Narrow on purpose, because a Stop hook runs on every turn and a slow or noisy one gets deleted:
#   - only when tracked files are modified or new files exist (a read-only turn is a no-op);
#   - only in a repo that declares a gate (`lefthook.yml`), running whatever it runs on commit;
#   - only over the CHANGED files (`--files-from-stdin`), so the cost is proportional to the turn.
#     Bare `lefthook run pre-commit` reads the INDEX, which is empty at the end of a turn, so
#     every glob-scoped command would skip and the gate would pass on work it never opened;
#   - once per tree state, so an unfixable failure blocks at most once until the tree changes;
#   - under a 60 s bound where `timeout` exists (it is not in the macOS base system).
#
# Fails OPEN on every error path: no jq, no git, no lefthook, an unreadable payload, a timeout.
set -uo pipefail

payload=$(cat 2> /dev/null) || exit 0
[ -n "$payload" ] || exit 0
command -v jq > /dev/null 2>&1 || exit 0
command -v git > /dev/null 2>&1 || exit 0
[ "$(printf '%s' "$payload" | jq -r '.stop_hook_active // false' 2> /dev/null)" = "true" ] && exit 0

cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2> /dev/null) || exit 0
[ -n "$cwd" ] && [ -d "$cwd" ] || exit 0
root=$(git -C "$cwd" rev-parse --show-toplevel 2> /dev/null) || exit 0
[ -f "$root/lefthook.yml" ] || [ -f "$root/.lefthook.yml" ] || exit 0
command -v lefthook > /dev/null 2>&1 || exit 0

# Changed files that still exist: modified or staged against HEAD, plus untracked. Deletions are
# not files a linter can open.
files=$(cd "$root" && {
  git diff --name-only HEAD 2> /dev/null
  git ls-files --others --exclude-standard 2> /dev/null
} | sort -u | while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done)
[ -n "$files" ] || exit 0

# One run per tree state. `status --porcelain` carries adds, deletes and untracked files; `diff
# HEAD` carries content, so an edit to an already-dirty file is re-checked.
state="${XDG_STATE_HOME:-$HOME/.local/state}/claude-verify-gate"
mkdir -p "$state" 2> /dev/null || exit 0
tree_id=$({
  git -C "$root" status --porcelain 2> /dev/null
  git -C "$root" diff HEAD 2> /dev/null
} | cksum | tr -d ' ') || exit 0
marker="$state/$tree_id"
[ -e "$marker" ] && exit 0

if command -v timeout > /dev/null 2>&1; then
  out=$(cd "$root" && printf '%s\n' "$files" | timeout 60 lefthook run pre-commit --files-from-stdin 2>&1)
  rc=$?
else
  out=$(cd "$root" && printf '%s\n' "$files" | lefthook run pre-commit --files-from-stdin 2>&1)
  rc=$?
fi
# 124 = timeout, 127 = lefthook could not run: fail open rather than strand the turn.
case $rc in 0 | 124 | 127) exit 0 ;; esac

: > "$marker" 2> /dev/null || exit 0
{
  echo "The repo's own commit gate does not pass on this turn's changed files, so the turn is not done yet."
  echo
  printf '%s\n' "$out" | tail -40
  echo
  echo "Fix what it reports, then finish. (This blocks at most once per state of the tree; if the"
  echo "failure is pre-existing or not yours to fix, say so and stop.)"
} >&2
exit 2
