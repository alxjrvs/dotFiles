#!/usr/bin/env bash
# Every suite in this directory, one entry point.
#
# There were eight suites and sixteen declarations of them — eight lefthook
# commands and eight CI steps — each carrying its own glob and its own paragraph
# of comment prose. Four of the lefthook globs were byte-identical
# (`{dot-claude/hooks/*.sh,dot-claude/hooks/tests/*}`) and three more were strict
# subsets of it, so touching one guard forked five suites off one trigger while
# the wiring claimed they were independently scoped. They were not.
#
# The list is DISCOVERED, not declared. A hardcoded roster is a second copy of
# the directory, and it had already rotted: `agents/guard-tester.md` promised
# "seven suites" against a directory holding nine. Anything matching `*.sh` here
# other than this file is a suite and runs; adding one is `git add`, and nothing
# else has to be told.
#
# Runs all of them even after one fails — a suite that hides the next one's
# result turns a green run into a claim nobody checked. Exit is nonzero if any
# failed, and the summary names which.
set -u

HERE=$(cd -- "$(dirname -- "$0")" && pwd)
SELF=$(basename -- "$0")

failed=''
ran=0

for suite in "$HERE"/*.sh; do
  [ -e "$suite" ] || continue
  name=$(basename -- "$suite")
  [ "$name" != "$SELF" ] || continue
  # A suite that is present but not executable is a staging mistake, not a pass.
  [ -x "$suite" ] || {
    failed="${failed} ${name}(not-executable)"
    ran=$((ran + 1))
    continue
  }

  ran=$((ran + 1))
  if ! "$suite"; then
    failed="${failed} ${name}"
  fi
done

[ "$ran" -gt 0 ] || {
  echo "hook-tests: no suites found in $HERE — this gate checked nothing" >&2
  exit 2
}

if [ -n "$failed" ]; then
  printf 'hook-tests: %d suites ran, FAILED:%s\n' "$ran" "$failed" >&2
  exit 1
fi
printf 'hook-tests: %d suites passed\n' "$ran"
