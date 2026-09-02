#!/usr/bin/env bash
#
# covers: the sources below. `all.sh --changed <files>` reads these lines to
# decide whether this suite has anything to say about a change; with no
# argument every suite runs regardless. A suite that declares nothing always
# runs, so forgetting a line costs time, never coverage.
# covers: dot-claude/hooks/worktree-port.sh
# Regression suite for worktree-port.sh.
#
# Its own harness for the same reason freshness.sh and wtremove.sh have theirs:
# run.sh asserts on a PreToolUse `permissionDecision`, and this hook returns no
# decision. Its observable effects are two — the port block it announces in
# `additionalContext`, and whether a `.env` on disk gained a `PORT=` line — so
# every case asserts one of those.
#
# No network and no remote: this hook never talks to one. Each case builds its
# own repo + linked worktree under `.claude/worktrees/`, because the `.env`
# cases mutate files and cannot share state. ~2s.
#
# READ THIS BEFORE TRUSTING A GREEN RUN. Five of the eleven cases assert the hook
# did NOT do something, and a hook that does nothing at all passes all five. The
# load-bearing three are `emits_block`, `writes_env` and `skip_env_symlink`. Both
# negative controls were run, and these are their measured results:
#
#   - stub hook (`exit 0` and nothing else): 5 failures — emits_block,
#     deterministic, distinct_names, writes_env, no_env_still_emits. That last
#     one is in the list because it asserts a block AND an absent .env, so a
#     silent hook fails it too.
#   - invert `writes_env` (assert NO PORT line) and `skip_env_existing_port`
#     (assert it IS overwritten): exactly 2 failures, those two.
#
# Re-run both if you change the hook. $1 overrides the hook path so a copy of
# this file with inverted expectations still points at the real one — the scar
# freshness.sh carries, where a relocated copy resolved $HERE to its own
# directory and "failed" every case with exit 127, proving nothing.
set -u

HERE=$(cd -- "$(dirname -- "$0")" && pwd)
HOOK=${1:-$(cd -- "$HERE/.." && pwd)/worktree-port.sh}
[ -x "$HOOK" ] || {
  echo "port-tests: no executable hook at $HOOK" >&2
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
export HOME=${TMPDIR:-/tmp}/port-tests-home.$$
mkdir -p "$HOME"

command -v jq > /dev/null 2>&1 || {
  echo "port-tests: jq is required" >&2
  exit 2
}

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/port-tests.XXXXXX") || exit 2
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

# Sets BOX rather than printing it: command substitution runs in a subshell, and
# freshness.sh has the scar from returning fixture state that way — the globals
# came back empty and the suite reported passes while running almost nothing.
# $2 is the .gitignore body, so a case can decide whether .env is ignored.
BOX=''
new_box() {
  local box=$ROOT/$1
  mkdir -p "$box/primary" || return 1
  q git init -b main "$box/primary" || return 1
  gq "$box/primary" config user.email t@example.com
  gq "$box/primary" config user.name Test
  gq "$box/primary" config commit.gpgsign false
  printf '%s\n' "${2-.env}" > "$box/primary/.gitignore"
  echo base > "$box/primary/README.md"
  gq "$box/primary" add README.md .gitignore
  gq "$box/primary" commit -m base
  mkdir -p "$box/primary/.claude/worktrees" || return 1
  BOX=$box
}

# A worktree cut the way the client cuts one: --no-track -B under
# .claude/worktrees, so it has no upstream and no commits of its own.
add_worktree() {
  q git -C "$1/primary" worktree add --no-track -B "$2" \
    "$1/primary/.claude/worktrees/$2" HEAD
}

run_hook() {
  printf '{"cwd":"%s","hook_event_name":"SessionStart"}' "$1" | "$HOOK" 2> /dev/null
}

# The announced block's first port, or empty if the hook said nothing.
base_of() {
  run_hook "$1" |
    jq -r '.hookSpecificOutput.additionalContext // empty' 2> /dev/null |
    grep -oE '\b2[0-9]{4}\b' 2> /dev/null | head -1
}

# --- 1. LOAD-BEARING: a worktree gets a block, and it is in range -----------
new_box block && box=$BOX && add_worktree "$box" wt && {
  b=$(base_of "$box/primary/.claude/worktrees/wt")
  if [ -n "$b" ] && [ "$b" -ge 20000 ] && [ "$b" -le 29999 ]; then ok; else
    note emits_block "expected a port in 20000-29999 in additionalContext, got '${b:-<nothing>}'"
  fi
}

# --- 2. stable across sessions ----------------------------------------------
# The whole reason the block is DERIVED and not allocated: it has to be the same
# next session, or a .env written once is wrong the second time.
new_box stable && box=$BOX && add_worktree "$box" wt && {
  wt=$box/primary/.claude/worktrees/wt
  first=$(base_of "$wt")
  second=$(base_of "$wt")
  if [ -n "$first" ] && [ "$first" = "$second" ]; then ok; else
    note deterministic "same worktree produced different blocks ($first vs $second)"
  fi
}

# --- 3. different worktrees get different blocks -----------------------------
new_box distinct && box=$BOX && add_worktree "$box" alpha && add_worktree "$box" beta && {
  a=$(base_of "$box/primary/.claude/worktrees/alpha")
  b=$(base_of "$box/primary/.claude/worktrees/beta")
  if [ -n "$a" ] && [ -n "$b" ] && [ "$a" != "$b" ]; then ok; else
    note distinct_names "alpha and beta share a block ($a / $b) — the derivation is not name-sensitive"
  fi
}

# --- 4. LOAD-BEARING: a gitignored .env actually gains the PORT --------------
new_box writeenv && box=$BOX && add_worktree "$box" wt && {
  wt=$box/primary/.claude/worktrees/wt
  printf 'API_KEY=xyz\n' > "$wt/.env"
  b=$(base_of "$wt")
  if grep -qx "PORT=$b" "$wt/.env" 2> /dev/null; then ok; else
    note writes_env "expected PORT=$b in the worktree's .env, got: $(tr '\n' ' ' < "$wt/.env")"
  fi
}

# --- 5. an explicit PORT was a decision — never override it -----------------
new_box hasport && box=$BOX && add_worktree "$box" wt && {
  wt=$box/primary/.claude/worktrees/wt
  printf 'PORT=3000\n' > "$wt/.env"
  before=$(cat "$wt/.env")
  run_hook "$wt" > /dev/null
  if [ "$(cat "$wt/.env")" = "$before" ]; then ok; else
    note skip_env_existing_port "hook rewrote a .env that already set PORT"
  fi
}

# --- 6. a .env git does NOT ignore must not be touched ----------------------
# Appending there would surface as a tracked diff an agent could commit. The
# .gitignore in this box deliberately does not list .env.
new_box notignored "*.log" && box=$BOX && add_worktree "$box" wt && {
  wt=$box/primary/.claude/worktrees/wt
  printf 'API_KEY=xyz\n' > "$wt/.env"
  before=$(cat "$wt/.env")
  run_hook "$wt" > /dev/null
  if [ "$(cat "$wt/.env")" = "$before" ]; then ok; else
    note skip_env_not_ignored "hook appended to a .env that git does not ignore"
  fi
}

# --- 7. LOAD-BEARING SAFETY: a symlinked .env points at the USER's file ------
# Appending through it would edit the primary checkout's real .env. Every other
# condition here passes (the target is a regular, gitignored file), so the
# symlink test is the only thing that can stop it.
new_box symlink && box=$BOX && add_worktree "$box" wt && {
  wt=$box/primary/.claude/worktrees/wt
  printf 'API_KEY=real\n' > "$box/primary/.env"
  ln -s "$box/primary/.env" "$wt/.env"
  before=$(cat "$box/primary/.env")
  run_hook "$wt" > /dev/null
  if [ "$(cat "$box/primary/.env")" = "$before" ]; then ok; else
    note skip_env_symlink "hook wrote THROUGH a symlink into the primary checkout's .env"
  fi
}

# --- 8. no .env → still announce the block, and never create one ------------
new_box noenv && box=$BOX && add_worktree "$box" wt && {
  wt=$box/primary/.claude/worktrees/wt
  b=$(base_of "$wt")
  if [ -n "$b" ] && [ ! -e "$wt/.env" ]; then ok; else
    note no_env_still_emits "expected a block with no .env created; block='${b:-<nothing>}' .env exists=$([ -e "$wt/.env" ] && echo yes || echo no)"
  fi
}

# --- 9. the user's own checkout is not an agent worktree --------------------
# freshness.sh has the scar that makes this worth asserting directly: a path
# comparison bug there misread the primary checkout as a linked worktree.
new_box primary && box=$BOX && {
  out=$(run_hook "$box/primary")
  if [ -z "$out" ]; then ok; else
    note skip_primary "hook spoke in the user's real checkout: $out"
  fi
}

# --- 10. a linked worktree outside .claude/worktrees is not ours ------------
new_box elsewhere && box=$BOX && {
  q git -C "$box/primary" worktree add --no-track -B manual "$box/manual" HEAD
  out=$(run_hook "$box/manual")
  if [ -z "$out" ]; then ok; else
    note skip_outside_claude "hook claimed a hand-made worktree outside .claude/worktrees"
  fi
}

# --- 11. a non-repo cwd must fail open, silently ----------------------------
mkdir -p "$ROOT/plain" && {
  if out=$(run_hook "$ROOT/plain") && [ -z "$out" ]; then ok; else
    note fails_open_nonrepo "expected exit 0 and no output outside a repo, got: $out"
  fi
}

total=$((pass + fail))
if [ "$fail" -gt 0 ]; then
  printf 'port-tests: %d/%d passed, %d FAILED%s\n' "$pass" "$total" "$fail" "$failures" >&2
  exit 1
fi
printf 'port-tests: %d/%d passed\n' "$pass" "$total"
