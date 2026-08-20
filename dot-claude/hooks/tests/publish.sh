#!/usr/bin/env bash
# Regression suite for worktree-publish.sh.
#
# Deliberately NOT folded into run.sh/cases.tsv, for the same reason
# freshness.sh isn't: that harness pipes a synthetic PreToolUse payload in and
# asserts on `.hookSpecificOutput.permissionDecision`, and this hook returns no
# decision at all. Its observable effect is "which refs exist on origin
# afterwards", which a TSV of commands cannot express.
#
# Every case builds its own sandbox (bare origin + primary clone + linked
# worktree) because the hook's whole job is to write to a remote — cases cannot
# share state. No network: `origin` is a bare repo on disk. ~3s.
#
# READ THIS BEFORE TRUSTING A GREEN RUN. Most cases here are "must NOT push"
# assertions, which a hook that does nothing at all passes trivially. The
# load-bearing case is `publishes_unpushed` — it requires a ref to actually
# appear on origin. If you change this hook, invert `publishes_unpushed`
# (expect no ref) and `skip_default_branch` (expect a ref) and confirm you get
# exactly two failures; that is what proves the harness discriminates rather
# than passing everything.
set -u

HERE=$(cd -- "$(dirname -- "$0")" && pwd)
# Overridable so a negative control (this file copied elsewhere with two
# expectations inverted) still points at the real hook — same rationale as
# freshness.sh, where a copy resolving $HERE to its own directory "failed"
# every case with exit 127 and proved nothing.
HOOK=${1:-$(cd -- "$HERE/.." && pwd)/worktree-publish.sh}
[ -x "$HOOK" ] || {
  echo "publish-tests: no executable hook at $HOOK" >&2
  exit 2
}

# Hermetic or worthless. Git exports GIT_DIR and friends into every hook it
# runs, so under lefthook these fixtures would silently resolve to the REAL
# repo; the agent env also carries GIT_CONFIG_* (commit identity, the op-agent
# credential helper), which must not reach a throwaway fixture and must never
# try to resolve a secret during a test run.
for v in $(env | sed -n 's/^\(GIT_[A-Za-z0-9_]*\)=.*/\1/p'); do
  unset "$v" 2> /dev/null || true
done
unset CDPATH
export GIT_CONFIG_NOSYSTEM=1
export HOME=${TMPDIR:-/tmp}/publish-tests-home.$$
mkdir -p "$HOME"

command -v jq > /dev/null 2>&1 || {
  echo "publish-tests: jq is required" >&2
  exit 2
}

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/publish-tests.XXXXXX") || exit 2
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

# Builds <box>/origin.git (bare, main) + <box>/primary (clone with a
# .claude/worktrees dir ready). Sets BOX rather than printing it: command
# substitution runs in a subshell, and freshness.sh has the scar from returning
# fixture state that way — the globals came back empty and the suite reported
# passes while running almost nothing.
BOX=''
new_box() {
  local box=$ROOT/$1
  mkdir -p "$box" || return 1
  q git init --bare -b main "$box/origin.git" || return 1
  q git clone "$box/origin.git" "$box/seed" || return 1
  gq "$box/seed" config user.email t@example.com
  gq "$box/seed" config user.name Test
  gq "$box/seed" config commit.gpgsign false
  echo base > "$box/seed/README.md"
  gq "$box/seed" add README.md
  gq "$box/seed" commit -m base
  gq "$box/seed" push -u origin main

  q git clone "$box/origin.git" "$box/primary" || return 1
  gq "$box/primary" config user.email t@example.com
  gq "$box/primary" config user.name Test
  gq "$box/primary" config commit.gpgsign false
  # origin/HEAD is what the hook reads to learn the default branch.
  gq "$box/primary" remote set-head origin main
  mkdir -p "$box/primary/.claude/worktrees" || return 1
  BOX=$box
}

# A linked worktree cut the way the client cuts one: `--no-track -B` under
# .claude/worktrees, so it has no upstream and no commits of its own.
add_worktree() {
  q git -C "$1/primary" worktree add --no-track -B "$2" \
    "$1/primary/.claude/worktrees/$2" HEAD
}

# One commit, so the worktree has something that exists on no remote.
commit_in() {
  echo work > "$1/work.txt"
  gq "$1" add work.txt
  gq "$1" commit -m "agent work"
}

run_hook() {
  printf '{"cwd":"%s","hook_event_name":"Stop"}' "$1" | "$HOOK" 2> /dev/null
}

# The assertion: does this branch exist on the bare origin?
on_origin() {
  git -C "$1/origin.git" show-ref --verify --quiet "refs/heads/$2"
}

# --- 1. THE LOAD-BEARING CASE: unpushed commits MUST be published -----------
new_box publish && box=$BOX && add_worktree "$box" wt && {
  commit_in "$box/primary/.claude/worktrees/wt"
  run_hook "$box/primary/.claude/worktrees/wt"
  if on_origin "$box" wt; then ok; else
    note publishes_unpushed "expected refs/heads/wt on origin — hook did not publish, so the delete would still be refused"
  fi
}

# --- 2. and it must set an upstream ------------------------------------------
# Not cosmetic: the upstream is what lets the CLIENT's own patch-id path work
# after the PR merges (`%(upstream:track)` must read `gone`, which requires an
# upstream to exist in the first place).
new_box upstream && box=$BOX && add_worktree "$box" wt && {
  wt=$box/primary/.claude/worktrees/wt
  commit_in "$wt"
  run_hook "$wt"
  if [ -n "$(git -C "$wt" config --get branch.wt.merge 2> /dev/null)" ]; then ok; else
    note sets_upstream "expected branch.wt.merge to be configured (git push -u), got none"
  fi
}

# --- 3. nothing to publish → no push, and no network ------------------------
new_box nothing && box=$BOX && add_worktree "$box" wt && {
  wt=$box/primary/.claude/worktrees/wt
  run_hook "$wt"
  if on_origin "$box" wt; then
    note skip_nothing_to_publish "hook pushed a branch with no commits of its own"
  else ok; fi
}

# --- 4. the default branch must NEVER be pushed from here -------------------
# A worktree on `main` is not an agent branch. This is the one check whose
# failure mode is "pushed main by accident", so it is asserted directly.
new_box defbranch && box=$BOX && {
  q git -C "$box/primary" worktree add --no-track -B main-copy \
    "$box/primary/.claude/worktrees/main-copy" HEAD
  wt=$box/primary/.claude/worktrees/main-copy
  # force the worktree onto the literal default branch name
  gq "$wt" branch -m main-copy main 2> /dev/null || true
  commit_in "$wt"
  before=$(git -C "$box/origin.git" rev-parse refs/heads/main)
  run_hook "$wt"
  if [ "$(git -C "$box/origin.git" rev-parse refs/heads/main)" = "$before" ]; then ok; else
    note skip_default_branch "hook pushed the DEFAULT BRANCH — origin/main moved"
  fi
}

# --- 5. the user's own primary checkout must NEVER be pushed from ------------
# It is not a linked worktree and not under .claude/worktrees; it must fail both
# conditions. freshness.sh has the scar that makes this worth asserting: a
# path-comparison bug there misread the primary checkout as a linked worktree.
new_box primary && box=$BOX && {
  q git -C "$box/primary" checkout -b sidebranch
  commit_in "$box/primary"
  run_hook "$box/primary"
  if on_origin "$box" sidebranch; then
    note skip_primary_checkout "hook pushed from the user's real checkout"
  else ok; fi
}

# --- 6. a linked worktree NOT under .claude/worktrees is not ours ------------
new_box elsewhere && box=$BOX && {
  q git -C "$box/primary" worktree add --no-track -B manual "$box/manual" HEAD
  commit_in "$box/manual"
  run_hook "$box/manual"
  if on_origin "$box" manual; then
    note skip_worktree_outside_claude "hook pushed a hand-made worktree outside .claude/worktrees"
  else ok; fi
}

# --- 7. detached HEAD → nothing to name, so nothing to push -----------------
new_box detached && box=$BOX && add_worktree "$box" wt && {
  wt=$box/primary/.claude/worktrees/wt
  commit_in "$wt"
  sha=$(git -C "$wt" rev-parse HEAD)
  gq "$wt" checkout --detach "$sha"
  before=$(git -C "$box/origin.git" for-each-ref --format='%(refname)' | sort)
  run_hook "$wt"
  if [ "$(git -C "$box/origin.git" for-each-ref --format='%(refname)' | sort)" = "$before" ]; then ok; else
    note skip_detached_head "hook created a ref on origin from a detached HEAD"
  fi
}

# --- 8. a stack-managed worktree is gh stack's business, not ours -----------
new_box stack && box=$BOX && add_worktree "$box" wt && {
  wt=$box/primary/.claude/worktrees/wt
  commit_in "$wt"
  gd=$(git -C "$wt" rev-parse --git-dir)
  gd=$(cd "$wt" && cd "$gd" && pwd -P)
  : > "$gd/gh-stack"
  run_hook "$wt"
  if on_origin "$box" wt; then
    note skip_stacked "hook single-pushed a layer of a gh stack"
  else ok; fi
}

# --- 9. no origin remote → nothing to publish to ----------------------------
new_box noremote && box=$BOX && add_worktree "$box" wt && {
  wt=$box/primary/.claude/worktrees/wt
  commit_in "$wt"
  gq "$box/primary" remote remove origin
  # Asserting on the exit code: there is no remote left to observe, and the
  # contract is that a missing remote is a quiet no-op rather than an error.
  if printf '{"cwd":"%s"}' "$wt" | "$HOOK" > /dev/null 2>&1; then ok; else
    note skip_no_origin "hook exited non-zero with no origin remote — must fail open"
  fi
}

# --- 10. already published → idempotent, no second push --------------------
new_box idempotent && box=$BOX && add_worktree "$box" wt && {
  wt=$box/primary/.claude/worktrees/wt
  commit_in "$wt"
  run_hook "$wt"
  first=$(git -C "$box/origin.git" rev-parse refs/heads/wt 2> /dev/null)
  run_hook "$wt"
  second=$(git -C "$box/origin.git" rev-parse refs/heads/wt 2> /dev/null)
  if [ -n "$first" ] && [ "$first" = "$second" ]; then ok; else
    note idempotent "second run changed origin/wt ($first → $second)"
  fi
}

# --- 11. never force: a diverged remote branch must survive ----------------
# The remote has a commit this worktree does not. A plain push is rejected; a
# forced one would destroy it. This is the case that must never regress.
new_box noforce && box=$BOX && add_worktree "$box" wt && {
  wt=$box/primary/.claude/worktrees/wt
  commit_in "$wt"
  # publish, then move the remote branch on independently
  run_hook "$wt"
  q git clone "$box/origin.git" "$box/other"
  gq "$box/other" config user.email t@example.com
  gq "$box/other" config user.name Test
  gq "$box/other" config commit.gpgsign false
  gq "$box/other" checkout -B wt origin/wt
  echo theirs > "$box/other/theirs.txt"
  gq "$box/other" add theirs.txt
  gq "$box/other" commit -m theirs
  gq "$box/other" push origin wt
  theirs=$(git -C "$box/origin.git" rev-parse refs/heads/wt)
  # now diverge locally and re-run
  echo mine > "$wt/mine.txt"
  gq "$wt" add mine.txt
  gq "$wt" commit -m mine
  run_hook "$wt"
  if [ "$(git -C "$box/origin.git" rev-parse refs/heads/wt)" = "$theirs" ]; then ok; else
    note never_force "hook force-pushed over a diverged remote branch — someone else's commit was discarded"
  fi
}

# --- 12. a dirty worktree still gets its COMMITS published ------------------
# Deliberately different from `boom code reap`, which refuses to push a dirty
# tree. Here dirty is not a reason to skip: uncommitted files are not being
# pushed, and the client blocks the delete on `dirty` and `unpushed`
# INDEPENDENTLY — force clears the first but never the second, so a dirty
# worktree still needs its commits on a remote before it can be force-closed.
new_box dirty && box=$BOX && add_worktree "$box" wt && {
  wt=$box/primary/.claude/worktrees/wt
  commit_in "$wt"
  echo uncommitted > "$wt/scratch.txt"
  echo more >> "$wt/work.txt"
  run_hook "$wt"
  if on_origin "$box" wt; then ok; else
    note publishes_when_dirty "hook skipped a dirty worktree, leaving it unforceable-closed"
  fi
}

total=$((pass + fail))
if [ "$fail" -gt 0 ]; then
  printf 'publish-tests: %d/%d passed, %d FAILED%s\n' "$pass" "$total" "$fail" "$failures" >&2
  exit 1
fi
printf 'publish-tests: %d/%d passed\n' "$pass" "$total"
