#!/usr/bin/env bash
# Regression suite for the two PreToolUse guards.
#
# The guards are 200+ lines of load-bearing, security-relevant shell — they are
# the only deterministic enforcement in the setup, and they had no tests. Two
# real defects shipped as a result: a `--dry-run` substring anywhere in a command
# disabled the direct-push-to-default rule entirely, and the same whole-string
# scan denied ordinary feature-branch pushes whose commit message said "main".
#
# Builds throwaway git fixtures in $TMPDIR, pipes a synthetic PreToolUse payload
# into each guard from inside the right fixture, and asserts on
# .hookSpecificOutput.permissionDecision. No network, no side effects, ~5s.
set -u

HERE=$(cd -- "$(dirname -- "$0")" && pwd)
CASES=${1:-$HERE/cases.tsv}
GUARD_DIR=$(cd -- "$HERE/.." && pwd)

# Hermetic or worthless. Git exports GIT_DIR / GIT_INDEX_FILE / GIT_PREFIX into
# every hook it runs, so under lefthook the fixtures silently resolved to the
# REAL repo — the suite passed standalone and failed five cases in pre-commit.
# The agent env also carries GIT_CONFIG_* (commit identity, the op-agent
# credential helper), which must not reach a throwaway fixture either.
for v in $(env | sed -n 's/^\(GIT_[A-Za-z0-9_]*\)=.*/\1/p'); do
  unset "$v" 2> /dev/null || true
done
unset CDPATH
export GIT_CONFIG_NOSYSTEM=1
export HOME=${TMPDIR:-/tmp}/guard-tests-home.$$
mkdir -p "$HOME"

command -v jq > /dev/null 2>&1 || {
  echo "guard-tests: jq is required" >&2
  exit 2
}

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/guard-tests.XXXXXX") || exit 2
cleanup() { rm -rf "$ROOT" "$HOME"; }
trap cleanup EXIT INT TERM

q() { "$@" > /dev/null 2>&1; }

# --- fixtures ---------------------------------------------------------------
# origin.git ── main
#   primary   on main, up to date
#   wt-a      feature-a, contains main  (ordinary in-flight branch)
#   wt-b      feature-b, held so others collide with it
#   wt-c      feature-c, stacked on feature-b and BEHIND main — so a bare
#             `gh pr create` is correctly denied while `--base feature-b` passes.
#             That pair is what distinguishes the fix from the bug.
build_fixtures() {
  q git init --bare -b main "$ROOT/origin.git" || return 1
  q git clone "$ROOT/origin.git" "$ROOT/primary" || return 1
  cd "$ROOT/primary" || return 1
  q git config user.email t@example.com
  q git config user.name Test
  q git config commit.gpgsign false
  echo base > README.md
  q git add README.md
  q git commit -m "base"
  q git push -u origin main

  # feature-b: the branch every collision case targets.
  q git branch feature-b
  q git push origin feature-b
  # feature-c stacks on feature-b.
  q git branch feature-c feature-b
  q git push origin feature-c

  # main advances AFTER the stack is cut, so feature-c is genuinely behind it.
  echo more >> README.md
  q git commit -am "advance main"
  q git push origin main

  # feature-a is cut from current main, so it is NOT behind.
  q git branch feature-a main
  q git push origin feature-a

  q git worktree add "$ROOT/wt-a" feature-a || return 1
  q git worktree add "$ROOT/wt-b" feature-b || return 1
  q git worktree add "$ROOT/wt-c" feature-c || return 1

  mkdir -p "$ROOT/nonrepo" || return 1
  return 0
}

fixture_dir() {
  case "$1" in
    primary) printf '%s' "$ROOT/primary" ;;
    wt-a) printf '%s' "$ROOT/wt-a" ;;
    wt-b) printf '%s' "$ROOT/wt-b" ;;
    wt-c) printf '%s' "$ROOT/wt-c" ;;
    nonrepo) printf '%s' "$ROOT/nonrepo" ;;
    *) return 1 ;;
  esac
}

guard_path() {
  case "$1" in
    rebase) printf '%s' "$GUARD_DIR/rebase-guard.sh" ;;
    worktree) printf '%s' "$GUARD_DIR/worktree-checkout-guard.sh" ;;
    *) return 1 ;;
  esac
}

if ! build_fixtures; then
  echo "guard-tests: could not build fixtures" >&2
  exit 2
fi

# --- run --------------------------------------------------------------------
pass=0
fail=0
failed_lines=''

while IFS=$'\t' read -r guard fixture command expected || [ -n "${guard:-}" ]; do
  case "${guard:-}" in '' | '#'*) continue ;; esac
  [ -n "${expected:-}" ] || continue

  gp=$(guard_path "$guard") || {
    echo "guard-tests: unknown guard '$guard'" >&2
    fail=$((fail + 1))
    continue
  }
  fd=$(fixture_dir "$fixture") || {
    echo "guard-tests: unknown fixture '$fixture'" >&2
    fail=$((fail + 1))
    continue
  }

  # `\n` in a case's command becomes a real newline, so multi-line commands and
  # heredoc bodies — both of which the guards must treat differently from a
  # single line — can still be written on one TSV row.
  command=$(printf '%b' "$command")

  out=$(cd "$fd" && printf '%s' "$command" |
    jq -Rs '{tool_name:"Bash", tool_input:{command:.}}' |
    "$gp" 2> /dev/null)
  actual=$(printf '%s' "$out" |
    jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2> /dev/null)
  [ -n "$actual" ] || actual=allow

  if [ "$actual" = "$expected" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    failed_lines="${failed_lines}
  [${guard}/${fixture}] expected ${expected}, got ${actual}
      \$ ${command}"
  fi
done < "$CASES"

if [ "$fail" -gt 0 ]; then
  printf 'guard-tests: %d passed, %d FAILED%s\n' "$pass" "$fail" "$failed_lines" >&2
  exit 1
fi
printf 'guard-tests: %d passed\n' "$pass"
