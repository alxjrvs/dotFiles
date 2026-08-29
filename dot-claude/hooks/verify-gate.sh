#!/usr/bin/env bash
# Stop hook: run the repo's OWN gate before an agent is allowed to call itself done.
#
# Everything else in dot-claude/hooks/ stops a bad ACTION. Nothing checked that the WORK is
# correct. The published guidance is the other way round — give Claude a check it can run and
# gate the stop on it — and the adversarial review here fires from PostToolUse on `git push`,
# which is after the work has already left the machine. This is the half that was missing.
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
#   - At most ONE block per session. There is no documented `stop_hook_active` field to lean
#     on, so the loop-breaker is ours: a marker under the state dir, keyed by session id. A
#     gate that can block forever is worse than no gate — it strands a session with no way out,
#     which is the failure mode that gets a hook removed rather than fixed.
#   - Under a timeout. A hung gate must not hang the session.
#
# Fails OPEN on every error path, like every other guard here: no jq, no git, no lefthook, an
# unreadable payload, a timeout — all exit 0. A verification gate that breaks a session because
# it could not run is a worse bug than the one it exists to catch.
set -uo pipefail

payload=$(cat 2> /dev/null) || exit 0
[ -n "$payload" ] || exit 0

command -v jq > /dev/null 2>&1 || exit 0
command -v git > /dev/null 2>&1 || exit 0

session=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2> /dev/null) || exit 0
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

# One block per session. The marker is written BEFORE blocking, so a crash between the two
# cannot produce a session that blocks twice.
state="${XDG_STATE_HOME:-$HOME/.local/state}/claude-verify-gate"
mkdir -p "$state" 2> /dev/null || exit 0
marker="$state/${session:-nosession}"
[ -e "$marker" ] && exit 0

# Run the repo's own commit gate, read-only from this hook's point of view: it is the same
# command the commit would run, so a pass here means the commit will pass too.
out=$(cd "$root" && timeout 120 lefthook run pre-commit 2>&1)
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
  echo "Fix what it reports, then finish. (This gate blocks at most once per session — if the"
  echo "failure is pre-existing or not yours to fix, say so and stop; it will not block again.)"
} >&2
exit 2
