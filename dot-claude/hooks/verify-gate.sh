#!/usr/bin/env bash
# Stop hook: run the repo's OWN gate before an agent is allowed to call itself done.
#
# Everything else in dot-claude/hooks/ stops a bad ACTION. Nothing checked that the WORK is
# correct; this is the half that was missing.
#
# Deliberately narrow, because a Stop hook runs on every turn and a slow or noisy one gets
# deleted:
#
#   - Only when the working tree has UNCOMMITTED changes to tracked files. That is the signal
#     that this turn did work and has not handed it to the commit gate yet. A read-only turn,
#     a question, a turn that already committed: all no-ops.
#   - Only in a repo that declares its own gate (`lefthook.yml`). This makes no judgement about
#     what "verified" means; it runs whatever the repo already runs on commit. A repo with no
#     gate gets no opinion from this hook.
#   - `--all-files`, and that is the whole correctness of this hook. Running bare
#     `lefthook run pre-commit` asks it to inspect the INDEX, and at the end of an agent turn
#     the index is empty -- the work is written but not staged. Fourteen of this repo's sixteen
#     pre-commit commands are `glob:`-scoped against `{staged_files}`, so all fourteen received
#     no files, skipped, and the gate reported success on work it had never opened. It passed
#     vacuously in the single most common case it exists for. `--all-files` makes the
#     `{staged_files}` templates resolve to real files, which is the only spelling that keeps
#     the promise below.
#   - Once per TREE STATE, not once per session, so a turn that changes nothing does not pay
#     for the gate twice and a turn that changes something is always re-checked. The old
#     session-keyed marker armed only after a failure, so a passing session re-ran the gate on
#     every dirty turn and a failing one stopped checking for good. See the marker block below
#     for why the key needs both `status --porcelain` and `diff HEAD`.
#   - Under a timeout. A hung gate must not hang the session. `--all-files` is slower than the
#     index-scoped run it replaces; that is the price of the gate meaning anything.
#
# The loop-breaker is the client's, not ours: `stop_hook_active` is set on the payload when
# Claude Code is already continuing because of a stop hook, and the client ends the turn after
# 8 consecutive blocks regardless. An earlier version of this file said no such field was
# documented and hand-rolled a session-keyed marker under the state dir to stand in for it.
#
# Fails OPEN on every error path, like every other guard here: no jq, no git, no lefthook, an
# unreadable payload, a timeout -- all exit 0. A verification gate that breaks a session because
# it could not run is a worse bug than the one it exists to catch.
set -uo pipefail

payload=$(cat 2> /dev/null) || exit 0
[ -n "$payload" ] || exit 0

command -v jq > /dev/null 2>&1 || exit 0
command -v git > /dev/null 2>&1 || exit 0

# Already continuing because of a stop hook: never block again on top of that.
[ "$(printf '%s' "$payload" | jq -r '.stop_hook_active // false' 2> /dev/null)" = "true" ] && exit 0

cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2> /dev/null) || exit 0
[ -n "$cwd" ] && [ -d "$cwd" ] || exit 0

# In a git repo?
root=$(git -C "$cwd" rev-parse --show-toplevel 2> /dev/null) || exit 0
[ -n "$root" ] || exit 0

# Does this repo declare its own gate? If not, this hook has no opinion to enforce.
[ -f "$root/lefthook.yml" ] || [ -f "$root/.lefthook.yml" ] || exit 0
command -v lefthook > /dev/null 2>&1 || exit 0

# Did this turn actually leave work uncommitted? `--quiet` exits 1 when there is a difference.
# Both halves: unstaged AND staged, so `git add` without a commit still counts as pending work.
if git -C "$root" diff --quiet 2> /dev/null && git -C "$root" diff --cached --quiet 2> /dev/null; then
  exit 0
fi

# One run per tree state, so a turn that edited nothing since the last check is free and a turn
# that edited something is always re-checked. Written BEFORE blocking, so a crash between the
# two cannot loop.
#
# BOTH halves are required, and the suite proves it: `status --porcelain` prints ` M f.txt`
# whatever the file now contains, so on its own it cannot tell an edit from no edit and the
# gate goes quiet for the rest of the session after one failure — exactly the defect the
# session-keyed marker had. `diff HEAD` carries the content; `status --porcelain` carries the
# adds, deletes and untracked files that a diff against HEAD does not show.
state="${XDG_STATE_HOME:-$HOME/.local/state}/claude-verify-gate"
mkdir -p "$state" 2> /dev/null || exit 0
tree_id=$({
  git -C "$root" status --porcelain 2> /dev/null
  git -C "$root" diff HEAD 2> /dev/null
} | cksum | tr -d ' ') || exit 0
marker="$state/$tree_id"
[ -e "$marker" ] && exit 0

# Run the repo's own commit gate over the WORKING TREE. See the `--all-files` note in the
# header: without it this inspects an empty index and passes on work it never opened.
out=$(cd "$root" && timeout 120 lefthook run pre-commit --all-files 2>&1)
rc=$?

# Timeout (124) or a lefthook that could not run at all: fail open rather than strand the turn.
[ "$rc" -eq 124 ] && exit 0
[ "$rc" -eq 0 ] && exit 0
[ "$rc" -eq 127 ] && exit 0

: > "$marker" 2> /dev/null || exit 0

# exit 2 blocks the stop and feeds stderr back as the reason.
{
  echo "The repo's own commit gate does not pass on the work in this tree, so this turn is not done yet."
  echo
  printf '%s\n' "$out" | tail -40
  echo
  echo "Fix what it reports, then finish. (This gate blocks at most once per state of the tree —"
  echo "if the failure is pre-existing or not yours to fix, say so and stop.)"
} >&2
exit 2
