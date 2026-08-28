#!/usr/bin/env bash
# Regression suite for the shared assertion scripts in `scripts/`.
#
# Every case here asserts the SAME property: a gate that checked nothing must
# not print `ok` and must not exit 0. That is not a hypothetical — on
# 2026-08-28 three of these scripts did exactly that:
#
#   $ scripts/settings-guardrails.sh dot-claude/does-not-exist.json
#   ok settings guardrails (dot-claude/does-not-exist.json)     EXIT=0
#   $ scripts/plist-validity.sh
#   ok plists ()                                                EXIT=0
#
# CI hands these scripts a literal path, or a `$(git ls-files …)` expansion that
# can be empty. So renaming a settings file, or moving `launchd/`, would have
# left the required `lint` check green while the deny floor and the launchd `~`
# bug went unchecked. `lefthook.yml` names this failure in its own canary
# comment — "an always-green canary is exactly the failure it exists to
# prevent" — and wrote a suite to stop it recurring there. This is that suite
# for the other three.
#
# The positive controls matter as much as the negative ones: a gate that fails
# on everything is no more useful than one that passes on everything.
set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1

pass=0
fail=0

# $1 = label, $2 = expected exit (0 = ok / non-0 = must fail), $3... = command
case_exit() {
  local label=$1 want=$2
  shift 2
  local out rc
  out=$("$@" 2>&1)
  rc=$?
  if { [ "$want" = 0 ] && [ "$rc" -eq 0 ]; } || { [ "$want" != 0 ] && [ "$rc" -ne 0 ]; }; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "  [$label] expected exit $want, got $rc"
    echo "      \$ $*"
    [ -n "$out" ] && echo "      $out"
  fi
}

# --- a named input that does not exist must FAIL, never be skipped -----------
case_exit guardrails_missing_path 1 ./scripts/settings-guardrails.sh dot-claude/does-not-exist.json
case_exit plist_missing_path 1 ./scripts/plist-validity.sh launchd/does-not-exist.plist
case_exit skillcap_missing_path 1 ./scripts/skill-description-cap.sh dot-claude/skills/nope/SKILL.md

# --- an EMPTY input list must FAIL: the caller's glob matched nothing --------
# `skill-description-cap.sh` is excluded here on purpose — it defaults to its
# own glob when called with no arguments, which is a deliberate convenience and
# still resolves to real files.
case_exit guardrails_no_args 1 ./scripts/settings-guardrails.sh
case_exit plist_no_args 1 ./scripts/plist-validity.sh

# --- positive controls: the real inputs must still PASS ----------------------
case_exit guardrails_real 0 ./scripts/settings-guardrails.sh dot-claude/settings.json
# Globbed, not named: a hardcoded plist label is an owner this suite would
# carry into every fork, and identity-drift.sh is right to reject one.
case_exit plist_real 0 ./scripts/plist-validity.sh launchd/*.plist
case_exit skillcap_default_glob 0 ./scripts/skill-description-cap.sh
case_exit context_budget_real 0 ./scripts/context-budget.sh

if [ "$fail" -gt 0 ]; then
  echo "gate-tests: $pass passed, $fail FAILED"
  exit 1
fi
echo "gate-tests: $pass passed"
