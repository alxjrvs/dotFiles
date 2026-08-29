#!/usr/bin/env bash
#
# covers: the sources below. `all.sh --changed <files>` reads these lines to
# decide whether this suite has anything to say about a change; with no
# argument every suite runs regardless. A suite that declares nothing always
# runs, so forgetting a line costs time, never coverage.
# covers: dot-claude/hooks/worktree-remove-guard.sh
# Regression suite for worktree-remove-guard.sh.
#
# Its own harness rather than a cases.tsv block, for the reason port.sh and
# freshness.sh have theirs: every verdict here depends on whether a PID in a
# lock file is RUNNING, which is state no fixture table can express. Each case
# needs a real linked worktree and a real lock naming a real (or really dead)
# process. ~1s, no network, no remote.
#
# READ THIS BEFORE TRUSTING A GREEN RUN. Nine of the sixteen cases assert the
# guard did NOT fire, and a hook that does nothing at all passes all nine. The
# load-bearing seven are the DENY cases. Both negative controls were run, and
# these are their measured results:
#
#   - stub hook (`exit 0` and nothing else): 7 failures, exactly the DENY cases.
#     (Written as 6 first, from counting the live-lock cases and forgetting
#     prune_expire_now — which is why this block records a measurement rather
#     than an expectation.)
#   - guard with the `kill -0` liveness test removed (treat every lock as live):
#     2 failures — remove_force_dead and rm_rf_dead, the two that prove the
#     guard distinguishes a live session from an abandoned worktree rather than
#     refusing every removal.
#
# Re-run both if you change the guard. $1 overrides the hook path so a copy of
# this file with inverted expectations still points at the real one.
set -u

HERE=$(cd -- "$(dirname -- "$0")" && pwd)
HOOK=${1:-$(cd -- "$HERE/.." && pwd)/worktree-remove-guard.sh}
[ -x "$HOOK" ] || {
  echo "wtremove-tests: no executable hook at $HOOK" >&2
  exit 2
}

# Hermetic or worthless. git exports GIT_DIR and friends into every hook it runs,
# so under lefthook these fixtures would resolve to the REAL repo; the agent env
# also carries GIT_CONFIG_* (commit identity, the op-agent credential helper),
# which must never reach a throwaway fixture or try to resolve a secret here.
for v in $(env | sed -n 's/^\(GIT_[A-Za-z0-9_]*\)=.*/\1/p'); do
  unset "$v" 2> /dev/null || true
done
unset CDPATH
export GIT_CONFIG_NOSYSTEM=1
export HOME=${TMPDIR:-/tmp}/wtremove-tests-home.$$
mkdir -p "$HOME"

command -v jq > /dev/null 2>&1 || {
  echo "wtremove-tests: jq is required" >&2
  exit 2
}

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/wtremove-tests.XXXXXX") || exit 2
cleanup() { rm -rf "$ROOT" "$HOME"; }
trap cleanup EXIT INT TERM

q() { "$@" > /dev/null 2>&1; }
gq() { git -C "$1" "${@:2}" > /dev/null 2>&1; }

pass=0
fail=0
failures=''
note() {
  fail=$((fail + 1))
  failures="${failures}
  [$1] $2"
}
ok() { pass=$((pass + 1)); }

REPO=$ROOT/repo
q mkdir -p "$REPO"
gq "$REPO" init -q -b main
gq "$REPO" config user.email t@example.com
gq "$REPO" config user.name Test
q touch "$REPO/f"
gq "$REPO" add f
gq "$REPO" commit -qm base

q mkdir -p "$REPO/.claude/worktrees"
LIVE=$REPO/.claude/worktrees/live
DEAD=$REPO/.claude/worktrees/dead
gq "$REPO" worktree add -q --no-track -b wt-live "$LIVE"
gq "$REPO" worktree add -q --no-track -b wt-dead "$DEAD"

# A pid that is certainly running: this script. A pid that is certainly not:
# a background command already reaped. (A recycled pid would be a false
# "alive", which fails SAFE — the guard would refuse a removal it could have
# allowed, never the reverse.)
sleep 0 &
DEADPID=$!
wait "$DEADPID" 2> /dev/null || true

printf 'claude session live (pid %s start now)\n' "$$" > "$REPO/.git/worktrees/live/locked"
printf 'claude session dead (pid %s start now)\n' "$DEADPID" > "$REPO/.git/worktrees/dead/locked"

# A third worktree with no lock at all — the normal state of one nobody is in.
NOLOCK=$REPO/.claude/worktrees/nolock
gq "$REPO" worktree add -q --no-track -b wt-nolock "$NOLOCK"
rm -f "$REPO/.git/worktrees/nolock/locked"

verdict() { # $1 = command -> prints DENY or ALLOW
  local out
  out=$(jq -cn --arg c "$1" --arg d "$REPO" \
    '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:$d,tool_input:{command:$c}}' |
    "$HOOK" 2> /dev/null)
  if [ -n "$out" ]; then printf 'DENY'; else printf 'ALLOW'; fi
}

case_is() { # $1 = name, $2 = expected, $3 = command
  local got
  got=$(verdict "$3")
  if [ "$got" = "$2" ]; then ok; else note "$1" "expected $2, got $got: $3"; fi
}

# --- a live lock is the whole point ------------------------------------------
case_is remove_force_live DENY "git worktree remove --force $LIVE"
case_is remove_f_live DENY "git worktree remove -f $LIVE"
case_is rm_rf_live DENY "rm -rf $LIVE"
case_is rm_rf_live_slash DENY "rm -fr $LIVE/"
# A leading `cd` does not change which path is named.
case_is cd_then_rm_live DENY "cd /tmp && rm -rf $LIVE"
# Inherited from _expand_interpreters: the payload is judged, not the wrapper.
case_is interp_rm_live DENY "bash -c \"rm -rf $LIVE\""

# --- a dead lock must NOT be refused -----------------------------------------
# This is the pair that proves the guard reads liveness rather than refusing
# every removal. An abandoned worktree is the common case and must stay cheap.
case_is remove_force_dead ALLOW "git worktree remove --force $DEAD"
case_is rm_rf_dead ALLOW "rm -rf $DEAD"
case_is remove_force_nolock ALLOW "git worktree remove --force $NOLOCK"

# --- git already refuses this one itself -------------------------------------
# Without --force git declines a locked worktree on its own, so the guard has no
# reason to duplicate the refusal (and a duplicated one would report the wrong
# cause).
case_is remove_noforce_live ALLOW "git worktree remove $LIVE"

# --- prune ------------------------------------------------------------------
case_is prune_expire_now DENY "git worktree prune --expire=now"
case_is prune_plain ALLOW "git worktree prune"

# --- must not fire out of turn ----------------------------------------------
case_is unrelated_rm ALLOW "rm -rf /tmp/some-unrelated-dir"
case_is plain_rm ALLOW "rm somefile"
case_is list ALLOW "git worktree list"
# Prose naming the command is not the command.
case_is echo_prose ALLOW "echo git worktree remove --force $LIVE"

# The lock files reference this test's own pid; drop them before the fixture is
# torn down so a recycled pid cannot make a stale lock look live to anything else.
rm -f "$REPO/.git/worktrees/live/locked" "$REPO/.git/worktrees/dead/locked"

if [ "$fail" -ne 0 ]; then
  echo "wtremove-tests: $pass passed, $fail FAILED$failures"
  exit 1
fi
echo "wtremove-tests: $pass passed"
