#!/usr/bin/env bash
# Hermetic suite for verify-gate.sh, the Stop hook that runs a repo's own commit gate over the
# turn's changed files before an agent may call itself done.
#
# The load-bearing cases are the ones where it must NOT block: a Stop hook runs on every turn,
# and one that blocks when it should not strands a session. So the no-op paths come first and
# the blocking cases last. A stub `lefthook` in a temp bin returns whatever exit code a case
# chooses, and REFUSES an invocation without `--files-from-stdin`: bare `lefthook run pre-commit`
# reads an empty index and passes vacuously, which is the regression this suite exists for.
set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/verify-gate.sh"

# Hermetic or worthless: git exports GIT_DIR / GIT_INDEX_FILE / GIT_PREFIX into every hook it
# runs and those override `git -C`, so without this block fixture commits land in the REAL repo.
for v in $(env | sed -n 's/^\(GIT_[A-Za-z0-9_]*\)=.*/\1/p'); do
  unset "$v" 2> /dev/null || true
done
unset CDPATH
export GIT_CONFIG_NOSYSTEM=1
for v in GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_PREFIX GIT_CONFIG_COUNT; do
  if [ -n "${!v:-}" ]; then
    echo "verifygate-tests: $v survived the environment scrub; refusing to run against a real repo" >&2
    exit 1
  fi
done

pass=0
fail=0

TMPROOT=$(mktemp -d "${TMPDIR:-/tmp}/verifygate-tests.XXXXXX") || {
  echo "verifygate-tests: mktemp failed; refusing to run against /" >&2
  exit 2
}
trap 'rm -rf "$TMPROOT"' EXIT

# A throwaway HOME so fixture commits never reach ~/.gitconfig's 1Password signing.
export HOME="$TMPROOT/home"
mkdir -p "$HOME"

BIN="$TMPROOT/bin"
mkdir -p "$BIN"
cat > "$BIN/lefthook" << 'STUB'
#!/usr/bin/env bash
echo "stub lefthook: $*"
case " $* " in
  *" --files-from-stdin "*) : ;;
  *)
    echo "stub lefthook: refusing; verify-gate must pass --files-from-stdin or it inspects an empty index" >&2
    exit 99
    ;;
esac
# The file list must actually arrive on stdin.
n=$(wc -l < /dev/stdin | tr -d ' ')
[ "$n" -gt 0 ] || { echo "stub lefthook: empty file list on stdin" >&2; exit 98; }
exit "$(cat "$LEFTHOOK_STUB_EXIT" 2> /dev/null || echo 0)"
STUB
chmod +x "$BIN/lefthook"
printf '0' > "$TMPROOT/exit"
export LEFTHOOK_STUB_EXIT="$TMPROOT/exit"

# $1 = label, $2 = expected exit, $3 = cwd, $4 = stop_hook_active (default false)
run_case() {
  local label=$1 want=$2 cwd=$3 active=${4:-false} out rc
  out=$(printf '{"session_id":"s","cwd":"%s","hook_event_name":"Stop","stop_hook_active":%s}' \
    "$cwd" "$active" |
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

# `core.hooksPath=/dev/null`: a bare `git init` on this machine may install a template hook that
# runs the real lefthook, recursively.
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
CLEAN=$(newrepo clean gate)
run_case clean_tree 0 "$CLEAN"

NOGATE=$(newrepo nogate)
dirty "$NOGATE"
run_case no_lefthook 0 "$NOGATE"

mkdir -p "$TMPROOT/plain"
run_case not_a_repo 0 "$TMPROOT/plain"
run_case missing_cwd 0 "$TMPROOT/does-not-exist"

PASSING=$(newrepo passing gate)
dirty "$PASSING"
printf '0' > "$TMPROOT/exit"
run_case gate_passes 0 "$PASSING"

# Untracked-only work is still work.
UNTRACKED=$(newrepo untracked gate)
echo new > "$UNTRACKED/new.txt"
run_case untracked_gate_passes 0 "$UNTRACKED"

STAGED=$(newrepo staged gate)
dirty "$STAGED"
gitf "$STAGED" add -A 2> /dev/null
run_case staged_gate_passes 0 "$STAGED"

# A deletion alone leaves nothing a linter can open: no run, no block.
DELETED=$(newrepo deleted gate)
rm "$DELETED/f.txt"
printf '1' > "$TMPROOT/exit"
run_case deletion_only_allows 0 "$DELETED"
printf '0' > "$TMPROOT/exit"

ACTIVE=$(newrepo active gate)
dirty "$ACTIVE"
printf '1' > "$TMPROOT/exit"
run_case stop_hook_active_allows 0 "$ACTIVE" true
printf '0' > "$TMPROOT/exit"

# --- must block, once per tree state -----------------------------------------
FAILING=$(newrepo failing gate)
dirty "$FAILING"
printf '1' > "$TMPROOT/exit"
run_case gate_fails_blocks 2 "$FAILING"
run_case same_tree_allows 0 "$FAILING"
dirty "$FAILING"
run_case changed_tree_blocks_again 2 "$FAILING"

# The bound is optional; the gate is not. Same failing gate on a PATH without `timeout`.
NOTO="$TMPROOT/no-timeout-bin"
mkdir -p "$NOTO"
for t in bash sh env git jq cat mkdir cksum tr sed head tail dirname sort wc; do
  p=$(command -v "$t" 2> /dev/null) && ln -s "$p" "$NOTO/$t"
done
ln -s "$BIN/lefthook" "$NOTO/lefthook"
NOTIMEOUT=$(newrepo notimeout gate)
dirty "$NOTIMEOUT"
printf '1' > "$TMPROOT/exit"
CASE_PATH="$NOTO" run_case gate_fails_blocks_without_timeout 2 "$NOTIMEOUT"

# --- fail open --------------------------------------------------------------
printf '124' > "$TMPROOT/exit"
run_case timeout_fails_open 0 "$FAILING"

if printf '' | PATH="$BIN:$PATH" "$HOOK" > /dev/null 2>&1; then pass=$((pass + 1)); else
  fail=$((fail + 1))
  echo "  [empty_payload] expected exit 0"
fi
if printf 'not json at all' | PATH="$BIN:$PATH" "$HOOK" > /dev/null 2>&1; then pass=$((pass + 1)); else
  fail=$((fail + 1))
  echo "  [garbage_payload] expected exit 0"
fi

if [ "$fail" -gt 0 ]; then
  echo "verifygate-tests: $pass passed, $fail FAILED"
  exit 1
fi
echo "verifygate-tests: $pass passed"
