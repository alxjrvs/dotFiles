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
GUARD=$(cd -- "$HERE/.." && pwd)/op-guard.sh

# op-guard decides from the command text alone and never invokes git, so the
# only hermeticity the suite needs is that `cd "$ROOT"` goes where it says.
unset CDPATH

command -v jq > /dev/null 2>&1 || {
  echo "guard-tests: jq is required" >&2
  exit 2
}

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/guard-tests.XXXXXX") || exit 2
cleanup() { rm -rf "$ROOT"; }
trap cleanup EXIT INT TERM

# --- run --------------------------------------------------------------------
# One scratch directory for every case: op-guard's verdict is decided from the
# command text alone, so no case needs a git fixture.
pass=0
fail=0
failed_lines=''

while IFS=$'\t' read -r command expected || [ -n "${command:-}" ]; do
  case "${command:-}" in '' | '#'*) continue ;; esac
  [ -n "${expected:-}" ] || continue

  # `\n` in a case's command becomes a real newline, so multi-line commands and
  # heredoc bodies — both of which the guards must treat differently from a
  # single line — can still be written on one TSV row.
  command=$(printf '%b' "$command")

  out=$(cd "$ROOT" && printf '%s' "$command" |
    jq -Rs '{tool_name:"Bash", tool_input:{command:.}}' |
    "$GUARD" 2> /dev/null)
  actual=$(printf '%s' "$out" |
    jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2> /dev/null)
  [ -n "$actual" ] || actual=allow

  if [ "$actual" = "$expected" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    failed_lines="${failed_lines}
  expected ${expected}, got ${actual}
      \$ ${command}"
  fi
done < "$CASES"

if [ "$fail" -gt 0 ]; then
  printf 'guard-tests: %d passed, %d FAILED%s\n' "$pass" "$fail" "$failed_lines" >&2
  exit 1
fi
printf 'guard-tests: %d passed\n' "$pass"
