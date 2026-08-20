#!/usr/bin/env bash
# Claude Code Stop/SessionEnd hook — publish an agent worktree's branch so
# DELETING the session is never refused.
#
# THE BUG THIS EXISTS FOR. Closing a finished agent session fails with
# "Worktree kept at … — has commits that are not pushed anywhere". Measured
# against 2.1.237 (decompiled, then reproduced): `deleteJob` clears a worktree
# only if
#
#     git rev-list --max-count=1 HEAD --not --remotes      # → empty
#
# or the branch's upstream reads exactly `gone` AND every commit patch-id
# matches origin/<default>. A fresh agent worktree is cut `--no-track`, so it
# has NO upstream at all — `%(upstream:track)` is empty, never the literal
# `gone` that second path requires — so the content-based escape can never
# fire, and a squash-merged branch stays blocked even though its content landed.
#
# `force` does NOT help. The decompiled chain is
#
#     else if (dirty && !gitError && !force)      keptReason = "dirty"
#     else if (!gitError && root && !onAnyRemote) keptReason = "unpushed"
#
# — force appears on the dirty arm and NOWHERE on the unpushed arm. There is no
# setting, no keystroke and no discard path for it either (checked). So the
# condition can only be FALSIFIED, never waived.
#
# WHY THIS RUNS AT IDLE AND NOT AT DELETE. There is no hook on the delete path.
# `WorktreeRemove` exists, but it is dispatched from inside
# `removeAgentWorktree`, which `deleteJob` only reaches AFTER the unpushed check
# has already returned — so by the time any removal hook could run, the refusal
# has happened. The push therefore has to be in place BEFORE the delete, and the
# last moment that is true is when the agent goes quiet. Hence Stop/SessionEnd.
#
# WHAT IT DOES. When an agent session sitting in a linked worktree finishes a
# turn and holds commits that exist on no remote, publish the branch:
#
#     git push -u origin HEAD:refs/heads/<branch>
#
# `--not --remotes` is then empty and the delete is instant. `-u` is not
# cosmetic: it configures the upstream, which is what lets the client's OWN
# patch-id path start working later — once the PR squash-merges and the remote
# branch is deleted, `%(upstream:track)` finally reads `gone` and the client
# clears the worktree by content without any help from us.
#
# SYNCHRONOUS, deliberately. Backgrounding would race the very gesture this
# exists to unblock: the user reads the agent's last message and presses delete.
# The cost is bounded and only paid on a turn that actually produced commits —
# a turn with nothing to publish exits before touching the network.
#
# NEVER FORCED, and never the default branch. This hook pushes where the
# rebase-before-push guard cannot see it (that guard tokenizes Bash tool calls;
# a hook's own git is not one), so the no-push-to-<default> half of that rule is
# re-enforced here rather than inherited. A non-fast-forward push simply fails
# and we exit 0.
#
# NOT WIRED ON SubagentStop. That event carries the PARENT process cwd, not the
# teammate's worktree — the same measured caveat already recorded for
# SubagentStart in dot-claude/CLAUDE.md — so it could not find the worktree it
# would need to publish. Stop fires inside the agent's own session, which is
# where the worktree actually is.
#
# EMITS NOTHING. A Stop hook's stdout is how it would block stopping; this hook
# has no business doing that, so it stays silent and is a pure side effect.
#
# FAILS OPEN, always. No jq, no origin, detached HEAD, offline, a rejected push,
# a stack-managed worktree — every one exits 0 and changes nothing. The failure
# mode is exactly today's behaviour: the delete is refused and the daily
# `boom code reap --push` sweep is the backstop.
set -u

quiet() { exit 0; }

payload=$(cat 2> /dev/null) || payload=''

# cwd from the payload, not $PWD: the payload is the documented contract, $PWD
# is an implementation detail of how the client spawns hooks. Same reasoning as
# worktree-freshness.sh.
if command -v jq > /dev/null 2>&1; then
  cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2> /dev/null)
fi
[ -n "${cwd:-}" ] || cwd=$PWD

cd "$cwd" 2> /dev/null || quiet
git rev-parse --git-dir > /dev/null 2>&1 || quiet
git remote get-url origin > /dev/null 2>&1 || quiet

# `timeout` is not on a stock macOS; treat its absence as "run unbounded"
# rather than as a reason to skip the work.
if command -v timeout > /dev/null 2>&1; then
  bound() { timeout "$@"; }
else
  bound() {
    shift
    "$@"
  }
fi

# --- only ever an agent worktree -------------------------------------------
# Two independent conditions, both required, because either alone is too loose:
#
#   1. a LINKED worktree (git-dir != git-common-dir). Resolved with `pwd -P` on
#      both sides, because comparing a symlink-resolved path to a logical one is
#      how worktree-freshness.sh once misread the PRIMARY CHECKOUT as a linked
#      worktree on macOS ($TMPDIR → /private/var/folders).
#   2. physically under a `.claude/worktrees/` directory — the client's own test
#      for "is this a worktree I created" (it refuses removal otherwise).
#
# Condition 1 alone would match any linked worktree the user made by hand for
# their own reasons; condition 2 alone would match a stray directory. The
# user's real checkout fails both, which is the point: this hook must never push
# from there.
gd=$(cd "$(git rev-parse --git-dir 2> /dev/null)" 2> /dev/null && pwd -P) || quiet
gcd=$(cd "$(git rev-parse --git-common-dir 2> /dev/null)" 2> /dev/null && pwd -P) || quiet
[ "$gd" != "$gcd" ] || quiet

top=$(git rev-parse --show-toplevel 2> /dev/null) || quiet
top=$(cd "$top" 2> /dev/null && pwd -P) || quiet
parent=$(dirname "$top")
[ "$(basename "$parent")" = worktrees ] || quiet
[ "$(basename "$(dirname "$parent")")" = .claude ] || quiet

# --- never the default branch ----------------------------------------------
branch=$(git symbolic-ref --short -q HEAD 2> /dev/null) || quiet
[ -n "$branch" ] || quiet

default_branch() {
  local d
  d=$(git symbolic-ref --short -q refs/remotes/origin/HEAD 2> /dev/null) &&
    [ -n "$d" ] && {
    printf '%s' "${d#origin/}"
    return 0
  }
  for d in main master; do
    git show-ref --verify --quiet "refs/remotes/origin/$d" && {
      printf '%s' "$d"
      return 0
    }
  done
  return 1
}

# A worktree sitting on the default branch is not an agent branch and must
# never be pushed from here. Unresolvable default → refuse rather than guess:
# this is the one check whose failure mode is "pushed main by accident".
base=$(default_branch) || quiet
[ "$branch" != "$base" ] || quiet

# --- leave stacks to gh stack ----------------------------------------------
# `gh stack` owns the cascading rebase and pushes every layer itself; a lone
# `git push` of the checked-out layer is the shape `boom code reap` explicitly
# refuses ("stack #N — publish with `gh stack submit`, not --push"). Stack state
# is per-worktree, in this worktree's own git dir.
[ -e "$gd/gh-stack" ] && quiet

# --- is there anything to publish? -----------------------------------------
# The client's exact test. Empty means every commit reachable from HEAD is on
# some remote-tracking ref, so the delete would already succeed and there is
# nothing to do — the common case, and it costs no network.
git rev-parse -q --verify HEAD > /dev/null 2>&1 || quiet
unpublished=$(git rev-list --max-count=1 HEAD --not --remotes 2> /dev/null) || quiet
[ -n "$unpublished" ] || quiet

# Explicit refspec rather than bare `HEAD`: it names exactly the remote branch
# being written, so this can never be talked into updating a differently-named
# ref. No --force, ever — a diverged branch is meant to fail here.
bound 60 git push --quiet -u origin "HEAD:refs/heads/$branch" > /dev/null 2>&1 || quiet

quiet
