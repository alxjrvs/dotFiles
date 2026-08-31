#!/usr/bin/env bash
#
# covers: the sources below. `all.sh --changed <files>` reads these lines to
# decide whether this suite has anything to say about a change; with no
# argument every suite runs regardless. A suite that declares nothing always
# runs, so forgetting a line costs time, never coverage.
# covers: hooks/claude-canary.sh
# Regression suite for hooks/claude-canary.sh.
#
# The canary reads the installed Claude Code client, which this suite cannot
# supply — so every case feeds it a SYNTHETIC bundle instead: a plain file
# holding, or deliberately missing, the string literals the real one carries.
# That is the whole reason the canary takes its target as $1.
#
# What this proves and what it cannot. It proves the DECISION LOGIC: which
# absence fails, which is silent, and that a bundle whose strings cannot be read
# is reported as a broken check rather than as good news. It cannot prove the
# literals are the right ones for a real client — only a re-measure against the
# actual binary does that, which is what a failure here is telling you to go do.
#
# READ THIS BEFORE TRUSTING A GREEN RUN. This suite's polarity is inverted from
# the hook suites: the load-bearing cases are the ones where the canary must
# FAIL. A canary that always exits 0 is the exact failure being guarded against —
# it reports all-clear forever. Both negative controls were run, and these are
# their measured results:
#
#   - stub that always exits 0: 4 of 5 fail. Every must-fail case, plus
#     missing_client, which wants the skip LINE and not merely exit 0.
#   - stub that always exits 1: 5 of 5 fail.
#
# The reason both numbers are that high is deliberate: no case asserts on the
# exit code alone. Each one also requires the message to name the hook that just
# became suspect, or to say the check itself is broken — because an operator
# reading a verify failure has only that line to act on, and "exit 1" with
# the wrong explanation would send them to re-measure the wrong defect.
set -u

HERE=$(cd -- "$(dirname -- "$0")" && pwd)
# ../../../hooks/ — the canary is a boom verify step, not a Claude hook, so it
# lives in the repo's own hooks/ rather than beside the agent hooks. Overridable
# as $1 for the negative controls above.
CANARY=${1:-$(cd -- "$HERE/../../.." && pwd)/hooks/claude-canary.sh}
[ -x "$CANARY" ] || {
  echo "canary-tests: no executable canary at $CANARY" >&2
  exit 2
}

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/canary-tests.XXXXXX") || exit 2
cleanup() { rm -rf "$ROOT"; }
trap cleanup EXIT INT TERM

pass=0
fail=0
failures=''
note() {
  fail=$((fail + 1))
  failures="${failures}
  [$1] $2"
}
ok() { pass=$((pass + 1)); }

ANCHOR='refs/remotes/origin/'
FRESH1='FETCH_HEAD'
FRESH2='86400000'

# A synthetic client: an executable that answers --version, with the requested
# literals embedded as data. Executable because the canary asks it for a version
# before fingerprinting it, and reads its own file for strings.
mk_bundle() {
  local f=$ROOT/$1
  shift
  {
    printf '#!/bin/sh\n'
    # shellcheck disable=SC2016 # $1 must reach the GENERATED script literally
    printf 'case "$1" in --version) echo "9.9.9 (Claude Code)";; esac\n'
    printf 'exit 0\n'
    printf '# padding to keep every literal well clear of the shebang line\n'
    for lit in "$@"; do printf '# %s\n' "$lit"; done
  } > "$f"
  chmod 755 "$f"
  printf '%s' "$f"
}

# --- 1. a client carrying every fingerprint → silent, exit 0 ---------------
b=$(mk_bundle intact "$ANCHOR" "$FRESH1" "$FRESH2")
out=$("$CANARY" "$b" 2>&1)
st=$?
if [ "$st" -eq 0 ] && [ -z "$out" ]; then ok; else
  note both_present "expected exit 0 and silence with all fingerprints present, got exit $st: $out"
fi

# --- 2. LOAD-BEARING: the freshness bug's literals are gone ---------------
b=$(mk_bundle nofresh "$ANCHOR")
out=$("$CANARY" "$b" 2>&1)
st=$?
if [ "$st" -ne 0 ] && printf '%s' "$out" | grep -q 'worktree-freshness'; then ok; else
  note freshness_gone "expected a non-zero exit naming worktree-freshness, got exit $st: $out"
fi

# --- 3. LOAD-BEARING: the anchor is gone → BROKEN CHECK, not good news ----
# This is the case that makes the rest trustworthy. It must not read as
# all-clear, and it must not read as "the bugs are fixed" either.
b=$(mk_bundle noanchor 'something else entirely')
out=$("$CANARY" "$b" 2>&1)
st=$?
if [ "$st" -ne 0 ] && printf '%s' "$out" | grep -qi 'no longer valid\|BROKEN CHECK'; then ok; else
  note anchor_gone "expected a non-zero exit reporting a broken check, got exit $st: $out"
fi

# --- 4. LOAD-BEARING: no strings at all → same, reported as broken -------
# An empty file is the degenerate form of "packaged so its strings cannot be
# read", which is the scenario that would otherwise make this canary lie.
printf '' > "$ROOT/empty"
chmod 755 "$ROOT/empty"
out=$("$CANARY" "$ROOT/empty" 2>&1)
st=$?
if [ "$st" -ne 0 ] && printf '%s' "$out" | grep -q 'fingerprint method is broken'; then ok; else
  note unreadable_strings "expected a non-zero exit reporting a broken method, got exit $st: $out"
fi

# --- 5. no client installed → skip, never a false alarm ------------------
out=$("$CANARY" "$ROOT/does-not-exist" 2>&1)
st=$?
if [ "$st" -eq 0 ] && printf '%s' "$out" | grep -q 'skipping'; then ok; else
  note missing_client "expected exit 0 and a skip line for an absent client, got exit $st: $out"
fi

total=$((pass + fail))
if [ "$fail" -gt 0 ]; then
  printf 'canary-tests: %d/%d passed, %d FAILED%s\n' "$pass" "$total" "$fail" "$failures" >&2
  exit 1
fi
printf 'canary-tests: %d/%d passed\n' "$pass" "$total"
