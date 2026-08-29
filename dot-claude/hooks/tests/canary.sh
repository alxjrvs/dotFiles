#!/usr/bin/env bash
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
#   - stub that always exits 0: 6 of 7 fail. Every must-fail case, plus
#     missing_client, which wants the skip LINE and not merely exit 0.
#   - stub that always exits 1: 7 of 7 fail.
#
# The reason both numbers are that high is deliberate: no case asserts on the
# exit code alone. Each one also requires the message to name the hook that just
# became suspect, or to say the check itself is broken — because an operator
# woken by the nightly notify has only that line to act on, and "exit 1" with
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
PUBLISH='has commits that are not pushed anywhere'

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
b=$(mk_bundle intact "$ANCHOR" "$FRESH1" "$FRESH2" "$PUBLISH")
out=$("$CANARY" "$b" 2>&1)
st=$?
if [ "$st" -eq 0 ] && [ -z "$out" ]; then ok; else
  note both_present "expected exit 0 and silence with all fingerprints present, got exit $st: $out"
fi

# --- 2. LOAD-BEARING: the freshness bug's literals are gone ---------------
b=$(mk_bundle nofresh "$ANCHOR" "$PUBLISH")
out=$("$CANARY" "$b" 2>&1)
st=$?
if [ "$st" -ne 0 ] && printf '%s' "$out" | grep -q 'worktree-freshness'; then ok; else
  note freshness_gone "expected a non-zero exit naming worktree-freshness, got exit $st: $out"
fi

# --- 3. LOAD-BEARING: the unpushed refusal string is gone -----------------
# Greps for `code reap` now. The hook this used to name was deleted 2026-08-28,
# and this assertion was the thing keeping that name alive in a shipped message.
b=$(mk_bundle nopublish "$ANCHOR" "$FRESH1" "$FRESH2")
out=$("$CANARY" "$b" 2>&1)
st=$?
if [ "$st" -ne 0 ] && printf '%s' "$out" | grep -q 'code reap'; then ok; else
  note publish_gone "expected a non-zero exit naming code reap, got exit $st: $out"
fi

# --- 4. LOAD-BEARING: both gone → both named in one run ------------------
# Not redundant with 2 and 3: an early `exit 1` on the first miss would hide the
# second, and a re-measure needs to know the full extent.
b=$(mk_bundle noneither "$ANCHOR")
out=$("$CANARY" "$b" 2>&1)
st=$?
if [ "$st" -ne 0 ] &&
  printf '%s' "$out" | grep -q 'worktree-freshness' &&
  printf '%s' "$out" | grep -q 'code reap'; then ok; else
  note both_gone "expected one non-zero run naming BOTH hooks, got exit $st: $out"
fi

# --- 5. LOAD-BEARING: the anchor is gone → BROKEN CHECK, not good news ----
# This is the case that makes the rest trustworthy. It must not read as
# all-clear, and it must not read as "the bugs are fixed" either.
b=$(mk_bundle noanchor 'something else entirely')
out=$("$CANARY" "$b" 2>&1)
st=$?
if [ "$st" -ne 0 ] && printf '%s' "$out" | grep -qi 'no longer valid\|BROKEN CHECK'; then ok; else
  note anchor_gone "expected a non-zero exit reporting a broken check, got exit $st: $out"
fi

# --- 6. LOAD-BEARING: no strings at all → same, reported as broken -------
# An empty file is the degenerate form of "packaged so its strings cannot be
# read", which is the scenario that would otherwise make this canary lie.
printf '' > "$ROOT/empty"
chmod 755 "$ROOT/empty"
out=$("$CANARY" "$ROOT/empty" 2>&1)
st=$?
if [ "$st" -ne 0 ] && printf '%s' "$out" | grep -q 'fingerprint method is broken'; then ok; else
  note unreadable_strings "expected a non-zero exit reporting a broken method, got exit $st: $out"
fi

# --- 7. no client installed → skip, never a nightly false alarm ----------
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
