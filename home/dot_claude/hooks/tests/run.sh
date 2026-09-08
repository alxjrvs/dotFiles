#!/usr/bin/env bash
# Regression suite for op-guard.sh — the guard whose verdict a fixture table can
# express.
#
# The guard is 400+ lines of load-bearing, security-relevant shell — the only
# deterministic enforcement in the setup — and the tokenizer it shares with the
# other guards once shipped two real defects (a `--dry-run` substring anywhere in
# a command disabled a whole rule; a whole-string scan denied on prose). The
# fixtures below outlive the push guard those defects were found in, because the
# same tokenizer still decides every `op` verdict.
#
# Pipes a synthetic PreToolUse payload into the guard from a scratch directory
# and asserts on .hookSpecificOutput.permissionDecision. No network, no side
# effects, a few seconds.
set -u

HERE=$(cd -- "$(dirname -- "$0")" && pwd)
CASES=${1:-$HERE/cases.tsv}
GUARD_DIR=$(cd -- "$HERE/.." && pwd)

# op-guard decides from the command text alone and never invokes git, so the
# only hermeticity the suite needs is that `cd "$fd"` goes where it says.
unset CDPATH

command -v jq > /dev/null 2>&1 || {
  echo "guard-tests: jq is required" >&2
  exit 2
}

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/guard-tests.XXXXXX") || exit 2
cleanup() { rm -rf "$ROOT"; }
trap cleanup EXIT INT TERM

# --- fixtures ---------------------------------------------------------------
# One scratch directory. op-guard's verdict is decided from the command text
# alone, so every case runs from a plain non-repo directory; the git fixtures
# the old push-guard cases needed went with those cases.
build_fixtures() {
  mkdir -p "$ROOT/nonrepo" || return 1
  return 0
}

fixture_dir() {
  case "$1" in
    nonrepo) printf '%s' "$ROOT/nonrepo" ;;
    *) return 1 ;;
  esac
}

guard_path() {
  case "$1" in
    op) printf '%s' "$GUARD_DIR/op-guard.sh" ;;
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
