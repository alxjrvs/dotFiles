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

# --- the cap must be able to SEE a multi-line description --------------------
# A YAML folded block put the indicator (`>-`) on the `description:` line, and
# the single-line parser scored that as one word — so any skill could carry an
# unbounded description past a gate reporting `ok (1 words)`. The cap is this
# script's entire purpose, and that spelling removed it.
case_exit skillcap_folded_over 1 ./scripts/skill-description-cap.sh scripts/tests/fixtures/folded-over-cap-SKILL.md
# Positive control: a SHORT folded block must still pass, or the fix would have
# replaced one broken gate with another.
case_exit skillcap_folded_under 0 ./scripts/skill-description-cap.sh scripts/tests/fixtures/folded-under-cap-SKILL.md

# --- the suite runner is itself a gate, and gets the same treatment ----------
# `dot-claude/hooks/tests/all.sh` discovers its roster from its own directory.
# That is what stops the roster rotting — but it is also the failure this file
# exists to catch: point it somewhere empty and a naive runner reports success
# for having run nothing, which is precisely how sixteen wired-up suites became
# zero without turning the `lint` check red.
#
# Run against fixture directories, never the real one: the real roster already runs
# as its own gate, and running it twice would only make this file slower. These
# four assert the runner's CONTRACT, not the suites' cases.
allsh=$(cd "$(dirname "$0")/../.." && pwd)/dot-claude/hooks/tests/all.sh
allfix=$(mktemp -d "${TMPDIR:-/tmp}/all-sh-fixture.XXXXXX")
trap 'rm -rf "$allfix"' EXIT INT TERM

mk_all() { # $1 = fixture subdir name; echoes the path to a copy of all.sh in it
  local d=$allfix/$1
  mkdir -p "$d"
  cp "$allsh" "$d/all.sh"
  chmod +x "$d/all.sh"
  printf '%s' "$d/all.sh"
}

# An empty directory means the glob that feeds this runner matched nothing.
# Exit 2, not 0 — "checked nothing" is a broken gate, not a passing one.
empty=$(mk_all empty)
case_exit all_empty_dir 2 "$empty"

# Positive control: a runner that fails on everything is no more useful than one
# that passes on everything.
okdir=$(mk_all ok)
printf '#!/bin/sh\nexit 0\n' > "$allfix/ok/a-suite.sh"
chmod +x "$allfix/ok/a-suite.sh"
case_exit all_passing_suite 0 "$okdir"

# A failing suite must surface even when another one passed — the runner keeps
# going so the caller sees every failure, but it must not exit 0 for it.
mixdir=$(mk_all mixed)
printf '#!/bin/sh\nexit 0\n' > "$allfix/mixed/a-suite.sh"
printf '#!/bin/sh\nexit 1\n' > "$allfix/mixed/b-suite.sh"
chmod +x "$allfix/mixed/a-suite.sh" "$allfix/mixed/b-suite.sh"
case_exit all_propagates_failure 1 "$mixdir"

# A suite committed without the executable bit is a staging mistake. Skipping it
# silently is the same all-clear-for-nothing this section guards against.
nxdir=$(mk_all nonexec)
printf '#!/bin/sh\nexit 0\n' > "$allfix/nonexec/a-suite.sh"
chmod -x "$allfix/nonexec/a-suite.sh"
case_exit all_nonexecutable_suite 1 "$nxdir"

if [ "$fail" -gt 0 ]; then
  echo "gate-tests: $pass passed, $fail FAILED"
  exit 1
fi
echo "gate-tests: $pass passed"
