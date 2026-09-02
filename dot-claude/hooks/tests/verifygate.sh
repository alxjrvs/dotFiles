#!/usr/bin/env bash
#
# covers: the sources below. `all.sh --changed <files>` reads these lines to
# decide whether this suite has anything to say about a change; with no
# argument every suite runs regardless. A suite that declares nothing always
# runs, so forgetting a line costs time, never coverage.
# covers: dot-claude/hooks/verify-gate.sh
# Hermetic suite for verify-gate.sh — the Stop hook that runs a repo's own commit gate before
# an agent may call itself done.
#
# Its load-bearing cases are the ones where it must NOT block. A Stop hook is the most
# dangerous shape in this directory: it runs on every turn, and one that blocks when it should
# not strands a session with no way out. So the no-op paths (clean tree, no gate declared, not
# a repo, unreadable payload), `stop_hook_active`, and the once-per-tree-state loop-breaker are
# asserted first, and the blocking cases last.
#
# No network, no lefthook on the real PATH: a stub `lefthook` is placed in a temp bin whose
# exit code each case chooses.
#
# THE STUB ASSERTS `--all-files`, and that is the point of this suite rather than a detail of
# it. The hook used to run bare `lefthook run pre-commit`, which inspects the INDEX; at the end
# of an agent turn the index is empty, so every `glob:`-scoped command in lefthook.yml
# received no files and skipped, and the gate reported success on work it had never opened. A
# stub that returns a canned exit code for any argument list cannot see that -- the previous
# version of this suite passed every case while the hook was vacuous. So the stub now refuses
# an invocation without `--all-files`, and `gate_passes` below is what fails if it regresses.
set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/verify-gate.sh"

# Hermetic or worthless — the same block run.sh carries, and for the same reason. Git exports
# GIT_DIR / GIT_INDEX_FILE / GIT_PREFIX into every hook it runs, and those OVERRIDE `git -C`.
# Without this, running under lefthook made every fixture commit land in the REAL repository:
# writing this suite without the block put three junk commits on its own branch before the
# mistake was noticed. The agent env also carries GIT_CONFIG_* (commit identity, the op-agent
# credential helper), which must not reach a throwaway fixture either.
for v in $(env | sed -n 's/^\(GIT_[A-Za-z0-9_]*\)=.*/\1/p'); do
  unset "$v" 2> /dev/null || true
done
unset CDPATH
export GIT_CONFIG_NOSYSTEM=1

# The block above is load-bearing, so it is asserted rather than assumed. If a GIT_* variable
# survives it, every fixture below is operating on whatever repo git was pointed at, and the
# suite is reporting on the wrong thing — which is not a failing test, it is a suite that
# silently commits to your branch.
for v in GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_PREFIX GIT_CONFIG_COUNT; do
  if [ -n "${!v:-}" ]; then
    echo "verifygate-tests: $v survived the environment scrub — refusing to run against a real repo" >&2
    exit 1
  fi
done

pass=0
fail=0

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

# A throwaway HOME, like run.sh's. Unsetting GIT_* above also removes the agent env's
# GIT_CONFIG_* pairs — which is where `commit.gpgsign=false` lives — so without this the
# fixtures fall back to the real ~/.gitconfig, whose `gpg.format = ssh` routes signing through
# 1Password. Every fixture commit then blocks on an auth prompt that will never come, and the
# suite hangs rather than fails, which is the worse of the two.
export HOME="$TMPROOT/home"
mkdir -p "$HOME"

# A stub lefthook that exits with whatever a case wrote into the marker file.
BIN="$TMPROOT/bin"
mkdir -p "$BIN"
cat > "$BIN/lefthook" << 'STUB'
#!/usr/bin/env bash
echo "stub lefthook: $*"
# The whole reason this suite exists. Without --all-files the real lefthook inspects an empty
# index and every glob-scoped command skips, so the gate passes on work it never read.
case " $* " in
  *" --all-files "*) : ;;
  *)
    echo "stub lefthook: refusing — verify-gate must pass --all-files or it inspects an empty index" >&2
    exit 99
    ;;
esac
exit "$(cat "$LEFTHOOK_STUB_EXIT" 2> /dev/null || echo 0)"
STUB
chmod +x "$BIN/lefthook"
printf '0' > "$TMPROOT/exit"
export LEFTHOOK_STUB_EXIT="$TMPROOT/exit"

# $1 = label, $2 = expected exit, $3 = cwd, $4 = session id, $5 = stop_hook_active (default false)
# CASE_PATH, when set, replaces the PATH the hook sees (the no-`timeout` case below).
run_case() {
  local label=$1 want=$2 cwd=$3 session=$4 active=${5:-false} out rc
  out=$(printf '{"session_id":"%s","cwd":"%s","hook_event_name":"Stop","stop_hook_active":%s}' \
    "$session" "$cwd" "$active" |
    PATH="${CASE_PATH:-$BIN:$PATH}" XDG_STATE_HOME="$TMPROOT/state" "$HOOK" 2>&1)
  rc=$?
  if [ "$rc" = "$want" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "  [$label] expected exit $want, got $rc"
    [ -n "$out" ] && echo "      $out" | head -5
  fi
}

# `-c core.hooksPath=/dev/null` on every fixture command: this machine sets
# `init.templateDir`, so a bare `git init` installs the house pre-commit hook into the fixture
# and every fixture commit then runs the REAL lefthook — which, in a fixture that declares a
# `lefthook.yml`, runs this very suite. Slow at best, recursive at worst.
# Signing off explicitly as well as via the throwaway HOME: belt and braces on the one failure
# mode that HANGS instead of failing.
gitf() {
  git -c core.hooksPath=/dev/null -c commit.gpgsign=false -c tag.gpgsign=false -C "$1" "${@:2}"
}

newrepo() { # $1 = name, $2 = "gate" to declare lefthook.yml
  local d="$TMPROOT/$1"
  mkdir -p "$d"
  gitf "$d" init -q 2> /dev/null
  gitf "$d" config user.email t@example.com
  gitf "$d" config user.name t
  echo base > "$d/f.txt"
  [ "${2:-}" = gate ] && echo "pre-commit:" > "$d/lefthook.yml"
  gitf "$d" add -A 2> /dev/null
  gitf "$d" commit -qm base 2> /dev/null
  printf '%s' "$d"
}

dirty() { echo "changed $RANDOM" >> "$1/f.txt"; }

# --- must NOT block ---------------------------------------------------------

# A clean tree means this turn left no uncommitted work to verify.
CLEAN=$(newrepo clean gate)
run_case clean_tree 0 "$CLEAN" s1

# A repo that declares no gate gets no opinion from this hook.
NOGATE=$(newrepo nogate)
dirty "$NOGATE"
run_case no_lefthook 0 "$NOGATE" s2

# Not a git repo at all.
mkdir -p "$TMPROOT/plain"
run_case not_a_repo 0 "$TMPROOT/plain" s3

# A cwd that does not exist — fail open rather than error.
run_case missing_cwd 0 "$TMPROOT/does-not-exist" s4

# The gate passes: dirty tree, gate declared, stub exits 0.
PASSING=$(newrepo passing gate)
dirty "$PASSING"
printf '0' > "$TMPROOT/exit"
run_case gate_passes 0 "$PASSING" s5

# Staged-but-uncommitted counts as pending work, and a passing gate still allows.
STAGED=$(newrepo staged gate)
dirty "$STAGED"
gitf "$STAGED" add -A 2> /dev/null
run_case staged_gate_passes 0 "$STAGED" s6

# Already continuing because of a stop hook: the client sets this, and blocking on top of it
# is how a session loops. Claude Code also ends the turn after 8 consecutive blocks on its own,
# which is why the hand-rolled session marker this hook used to carry is gone.
ACTIVE=$(newrepo active gate)
dirty "$ACTIVE"
printf '1' > "$TMPROOT/exit"
run_case stop_hook_active_allows 0 "$ACTIVE" s10 true
printf '0' > "$TMPROOT/exit"

# --- must block, once per tree state -----------------------------------------

FAILING=$(newrepo failing gate)
dirty "$FAILING"
printf '1' > "$TMPROOT/exit"
run_case gate_fails_blocks 2 "$FAILING" s7

# The loop-breaker, keyed by TREE STATE: the same unchanged tree must not be blocked twice, or
# a failure the agent cannot fix strands the session forever. A different session id makes no
# difference — the tree is what was already judged.
run_case same_tree_allows 0 "$FAILING" s7
run_case same_tree_other_session_allows 0 "$FAILING" s8

# Change the work and the gate gets to speak again. The old session-keyed marker could not do
# this: it went quiet for the rest of the session after one failure, however much changed.
dirty "$FAILING"
run_case changed_tree_blocks_again 2 "$FAILING" s7

# --- the bound is optional; the gate is not -----------------------------------
# `timeout` is not in the macOS base system. The hook used to call it unguarded, and a missing
# binary is rc 127 — which the fail-open arm read as "lefthook could not run", so the Stop gate
# enforced nothing on the OS it is written for, and this suite could not see it because it only
# ever ran where `timeout` exists. Same failing gate, on a PATH that carries everything the hook
# needs except `timeout`: it must still block.
NOTO="$TMPROOT/no-timeout-bin"
mkdir -p "$NOTO"
for t in bash sh env git jq cat mkdir cksum tr sed head tail dirname; do
  p=$(command -v "$t" 2> /dev/null) && ln -s "$p" "$NOTO/$t"
done
ln -s "$BIN/lefthook" "$NOTO/lefthook"
NOTIMEOUT=$(newrepo notimeout gate)
dirty "$NOTIMEOUT"
printf '1' > "$TMPROOT/exit"
CASE_PATH="$NOTO" run_case gate_fails_blocks_without_timeout 2 "$NOTIMEOUT" s11

# --- fail open --------------------------------------------------------------

# A timeout must not strand the turn (124 is timeout's exit).
printf '124' > "$TMPROOT/exit"
run_case timeout_fails_open 0 "$FAILING" s9

# An empty payload.
if printf '' | PATH="$BIN:$PATH" "$HOOK" > /dev/null 2>&1; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  echo "  [empty_payload] expected exit 0"
fi

# Garbage that is not JSON.
if printf 'not json at all' | PATH="$BIN:$PATH" "$HOOK" > /dev/null 2>&1; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  echo "  [garbage_payload] expected exit 0"
fi

if [ "$fail" -gt 0 ]; then
  echo "verifygate-tests: $pass passed, $fail FAILED"
  exit 1
fi
echo "verifygate-tests: $pass passed"
