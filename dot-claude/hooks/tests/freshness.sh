#!/usr/bin/env bash
#
# covers: the sources below. `all.sh --changed <files>` reads these lines to
# decide whether this suite has anything to say about a change; with no
# argument every suite runs regardless. A suite that declares nothing always
# runs, so forgetting a line costs time, never coverage.
# covers: dot-claude/hooks/worktree-freshness.sh
# Regression suite for worktree-freshness.sh.
#
# Deliberately NOT folded into run.sh/cases.tsv. That harness pipes a synthetic
# PreToolUse payload in and asserts on `.hookSpecificOutput.permissionDecision`;
# this hook decides nothing and instead MUTATES a git worktree, so the assertion
# is "which commit is HEAD on afterwards". A TSV of commands cannot express
# per-case repo state, and bending run.sh to cover both would make the guard
# suite harder to read for no gain.
#
# Every case builds its own sandbox (bare origin + primary clone + linked
# worktrees) because the hook's whole job is to move refs — cases cannot share
# state. No network: `origin` is a bare repo on disk. ~4s.
#
# Both directions are asserted on purpose. A hook that never fires passes every
# "did not clobber my work" case trivially, so `ff_virgin_behind` (it MUST move)
# is what distinguishes enforcement from a no-op, and `skip_*` are what
# distinguish enforcement from a blunt `reset --hard`.
set -u

HERE=$(cd -- "$(dirname -- "$0")" && pwd)
# Overridable so a negative control (this file copied elsewhere with two
# expectations inverted) still points at the real hook. Without it the copy
# resolved $HERE to its own directory, found no hook, and "failed" 8 cases with
# exit 127 — a control that proves nothing except that the copy was broken.
HOOK=${1:-$(cd -- "$HERE/.." && pwd)/worktree-freshness.sh}
[ -x "$HOOK" ] || {
  echo "freshness-tests: no executable hook at $HOOK" >&2
  exit 2
}

# Hermetic or worthless — same reasoning as run.sh. Git exports GIT_DIR and
# friends into every hook it runs, so under lefthook these fixtures would
# silently resolve to the REAL repo; the agent env also carries GIT_CONFIG_*
# (commit identity, the op-agent credential helper), which must not reach a
# throwaway fixture and must not try to resolve a secret during a test run.
for v in $(env | sed -n 's/^\(GIT_[A-Za-z0-9_]*\)=.*/\1/p'); do
  unset "$v" 2> /dev/null || true
done
unset CDPATH
export GIT_CONFIG_NOSYSTEM=1
export HOME=${TMPDIR:-/tmp}/freshness-tests-home.$$
mkdir -p "$HOME"

command -v jq > /dev/null 2>&1 || {
  echo "freshness-tests: jq is required" >&2
  exit 2
}

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/freshness-tests.XXXXXX") || exit 2
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

# Builds: <box>/origin.git (bare, main), <box>/primary (clone).
# `origin/main` in the clone is deliberately left STALE — one commit behind the
# bare repo — which is exactly the state the 24h FETCH_HEAD skip leaves a real
# machine in. TIP is the commit the hook must reach; STALE is the one it starts
# from.
STALE=''
TIP=''
BOX=''
# Sets the globals BOX/STALE/TIP rather than printing the path. Deliberate: an
# earlier version returned the path via `box=$(new_box x)`, and command
# substitution runs in a subshell, so STALE and TIP came back EMPTY in every
# case. `git worktree add ... ""` then failed, `&&` skipped the whole case body,
# and the suite reported "4 passed" while silently running almost nothing.
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
  STALE=$(git -C "$box/primary" rev-parse HEAD)

  # origin moves on; the primary clone is NOT told.
  echo more >> "$box/seed/README.md"
  gq "$box/seed" commit -am advance
  gq "$box/seed" push origin main
  TIP=$(git -C "$box/seed" rev-parse HEAD)
  BOX=$box
}

# A linked worktree cut the way the client cuts one: `--no-track -B` at the
# stale base, so it has no upstream and no commits of its own.
add_worktree() {
  q git -C "$1/primary" worktree add --no-track -B "$2" "$1/$2" "$3"
}

run_hook() {
  printf '{"cwd":"%s","hook_event_name":"SessionStart"}' "$1" |
    "$HOOK" 2> /dev/null
}
head_of() { git -C "$1" rev-parse HEAD 2> /dev/null; }
ctx_of() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // ""' 2> /dev/null; }

# --- 1. the load-bearing case: a virgin worktree behind origin MUST move ------
new_box ff && box=$BOX && add_worktree "$box" wt "$STALE" && {
  out=$(run_hook "$box/wt")
  got=$(head_of "$box/wt")
  if [ "$got" = "$TIP" ]; then ok; else
    note ff_virgin_behind "expected HEAD=$TIP (origin tip), got $got — hook did not fast-forward"
  fi
  case "$(ctx_of "$out")" in
    *fast-forwarded*) ok ;;
    *) note ff_virgin_behind_context "expected a fast-forward notice, got: $(ctx_of "$out")" ;;
  esac
}

# --- 2. a branch with its own commits must NOT be touched --------------------
new_box diverged && box=$BOX && add_worktree "$box" wt "$STALE" && {
  echo own > "$box/wt/own.txt"
  gq "$box/wt" add own.txt
  gq "$box/wt" commit -m "agent work"
  before=$(head_of "$box/wt")
  out=$(run_hook "$box/wt")
  if [ "$(head_of "$box/wt")" = "$before" ]; then ok; else
    note skip_diverged "hook moved HEAD on a branch carrying its own commits — work would be lost"
  fi
  case "$(ctx_of "$out")" in
    *diverged*) ok ;;
    *) note skip_diverged_context "expected a divergence advisory, got: $(ctx_of "$out")" ;;
  esac
}

# --- 3. a dirty worktree must NOT be touched --------------------------------
new_box dirty && box=$BOX && add_worktree "$box" wt "$STALE" && {
  echo scribble >> "$box/wt/README.md"
  before=$(head_of "$box/wt")
  out=$(run_hook "$box/wt")
  if [ "$(head_of "$box/wt")" = "$before" ]; then ok; else
    note skip_dirty "hook moved HEAD with uncommitted changes present"
  fi
  case "$(ctx_of "$out")" in
    *uncommitted*) ok ;;
    *) note skip_dirty_context "expected an uncommitted-changes advisory, got: $(ctx_of "$out")" ;;
  esac
}

# --- 4. the primary checkout must never have its working tree moved ----------
# It may (and should) get its refs refreshed, but a hook that checks out code in
# the user's own clone would be intolerable.
new_box primary && box=$BOX && {
  before=$(head_of "$box/primary")
  run_hook "$box/primary" > /dev/null
  if [ "$(head_of "$box/primary")" = "$before" ]; then ok; else
    note skip_primary "hook moved HEAD in the primary checkout"
  fi
}

# --- 5. an upstream that is not the default branch must be respected ---------
# The hook prefers `branch.<name>.merge` over origin/<default>; retargeting a
# tracked branch at main would be the opposite of respecting its intent.
new_box upstream && box=$BOX && {
  gq "$box/seed" checkout -b side "$STALE"
  echo side > "$box/seed/side.txt"
  gq "$box/seed" add side.txt
  gq "$box/seed" commit -m side
  gq "$box/seed" push -u origin side
  side_tip=$(git -C "$box/seed" rev-parse HEAD)
  gq "$box/primary" fetch origin "+refs/heads/side:refs/remotes/origin/side"
  q git -C "$box/primary" worktree add -B wt "$box/wt" "$STALE"
  gq "$box/wt" config "branch.wt.remote" origin
  gq "$box/wt" config "branch.wt.merge" refs/heads/side
  run_hook "$box/wt" > /dev/null
  got=$(head_of "$box/wt")
  if [ "$got" = "$side_tip" ]; then ok; else
    note upstream_respected "expected HEAD=$side_tip (origin/side), got $got"
  fi
  if [ "$got" != "$TIP" ]; then ok; else
    note upstream_not_main "hook retargeted a tracked branch at origin/main"
  fi
}

# --- 6. already current: silent, no output ----------------------------------
new_box current && box=$BOX && {
  gq "$box/primary" fetch origin "+refs/heads/main:refs/remotes/origin/main"
  add_worktree "$box" wt "$TIP"
  out=$(run_hook "$box/wt")
  if [ -z "$out" ]; then ok; else
    note silent_when_current "expected no output when already at origin tip, got: $out"
  fi
}

# --- 7. fail-open cases: never error, never emit ----------------------------
mkdir -p "$ROOT/nonrepo"
for spot in "$ROOT/nonrepo" "$ROOT/does-not-exist"; do
  out=$(run_hook "$spot")
  rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$out" ]; then ok; else
    note fail_open "cwd=$spot expected silent exit 0, got rc=$rc out=$out"
  fi
done

# A repo with no `origin` remote at all must be inert, not an error.
q git init -b main "$ROOT/noremote"
gq "$ROOT/noremote" config user.email t@example.com
gq "$ROOT/noremote" config user.name Test
gq "$ROOT/noremote" config commit.gpgsign false
echo x > "$ROOT/noremote/f"
gq "$ROOT/noremote" add f
gq "$ROOT/noremote" commit -m x
out=$(run_hook "$ROOT/noremote")
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then ok; else
  note fail_open_noremote "expected silent exit 0 without an origin remote, got rc=$rc out=$out"
fi

# --- 8. detached HEAD in a worktree: untouched ------------------------------
new_box detached && box=$BOX && add_worktree "$box" wt "$STALE" && {
  gq "$box/wt" checkout --detach "$STALE"
  before=$(head_of "$box/wt")
  run_hook "$box/wt" > /dev/null
  if [ "$(head_of "$box/wt")" = "$before" ]; then ok; else
    note skip_detached "hook moved a detached HEAD"
  fi
}

if [ "$fail" -gt 0 ]; then
  printf 'freshness-tests: %d passed, %d FAILED%s\n' "$pass" "$fail" "$failures" >&2
  exit 1
fi
printf 'freshness-tests: %d passed\n' "$pass"
