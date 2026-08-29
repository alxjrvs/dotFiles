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
#
# `--changed <file>...` runs only the suites that cover one of those files.
# Measured, the full sweep is ~18s and one suite (run.sh, the 264-case tokenizer
# table) is 10s of it — paid in full on every commit that touches any guard,
# which is the most frequently edited code in the repo. Editing worktree-port.sh
# now costs 1.6s instead of 18s.
#
# The mapping is DECLARED BY EACH SUITE, in `# covers:` lines, and discovered
# here — the same reason the roster itself is discovered. A table in this file
# would be a second copy of a relationship the suites already know, and the
# hardcoded roster it replaced had already rotted once. A suite that declares
# nothing always runs, so a forgotten line costs time, never coverage.
#
# CI passes no argument and runs everything. That asymmetry is deliberate: local
# selection is a latency optimisation, and the full sweep still gates the merge,
# so a wrong `covers:` line cannot let a regression through.
set -u

HERE=$(cd -- "$(dirname -- "$0")" && pwd)
SELF=$(basename -- "$0")

changed=''
if [ "${1:-}" = "--changed" ]; then
  shift
  changed=$*
  # An empty file list after --changed means the caller's glob matched nothing.
  # Run everything rather than nothing: this gate must never silently pass by
  # checking zero suites.
  [ -n "$changed" ] || changed=''
fi

# Does $1 (a suite) cover any of the changed files?
covers_changed() {
  _srcs=$(sed -n 's/^# covers:[[:space:]]*//p' "$1")
  # Declares nothing → always runs.
  [ -n "$_srcs" ] || return 0
  for _s in $_srcs; do
    for _c in $changed; do
      # Match on suffix so an absolute or ./-prefixed path from a caller still
      # lines up with the repo-relative path a suite declares.
      case "$_c" in
        *"$_s") return 0 ;;
      esac
    done
  done
  return 1
}

failed=''
ran=0
skipped=0

for suite in "$HERE"/*.sh; do
  [ -e "$suite" ] || continue
  name=$(basename -- "$suite")
  [ "$name" != "$SELF" ] || continue

  if [ -n "$changed" ] && ! covers_changed "$suite"; then
    skipped=$((skipped + 1))
    continue
  fi
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

# Zero suites RUN is fine under --changed (nothing relevant was touched) but
# never fine otherwise — that is the "gate checked nothing" failure this repo
# has paid for elsewhere. Distinguish the two rather than collapsing them.
if [ "$ran" -eq 0 ]; then
  if [ -n "$changed" ]; then
    printf 'hook-tests: no suite covers the changed files (%d skipped)\n' "$skipped"
    exit 0
  fi
  echo "hook-tests: no suites found in $HERE — this gate checked nothing" >&2
  exit 2
fi

if [ -n "$failed" ]; then
  printf 'hook-tests: %d suites ran, FAILED:%s\n' "$ran" "$failed" >&2
  exit 1
fi
if [ "$skipped" -gt 0 ]; then
  printf 'hook-tests: %d suites passed, %d not covering the change (CI runs all)\n' "$ran" "$skipped"
else
  printf 'hook-tests: %d suites passed\n' "$ran"
fi
