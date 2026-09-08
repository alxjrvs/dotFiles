#!/usr/bin/env bash
# Every suite in this directory, one entry point.
#
# The roster is DISCOVERED from the directory, so adding a suite needs no edit
# here: anything matching `*.sh` other than this file is a suite and runs.
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

# Zero suites run is the "gate checked nothing" failure, never a pass.
if [ "$ran" -eq 0 ]; then
  echo "hook-tests: no suites found in $HERE — this gate checked nothing" >&2
  exit 2
fi

if [ -n "$failed" ]; then
  printf 'hook-tests: %d suites ran, FAILED:%s\n' "$ran" "$failed" >&2
  exit 1
fi
printf 'hook-tests: %d suites passed\n' "$ran"
