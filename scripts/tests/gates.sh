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
case_exit skillcap_missing_path 1 ./scripts/description-cap.sh dot-claude/skills/nope/SKILL.md

# --- an EMPTY input list must FAIL: the caller's glob matched nothing --------
# `description-cap.sh` is excluded here on purpose — it defaults to its
# own glob when called with no arguments, which is a deliberate convenience and
# still resolves to real files.
case_exit guardrails_no_args 1 ./scripts/settings-guardrails.sh
case_exit plist_no_args 1 ./scripts/plist-validity.sh

# --- positive controls: the real inputs must still PASS ----------------------
case_exit guardrails_real 0 ./scripts/settings-guardrails.sh dot-claude/settings.json
# Globbed, not named: a hardcoded plist label is an owner this suite would
# carry into every fork, and identity-drift.sh is right to reject one.
case_exit plist_real 0 ./scripts/plist-validity.sh launchd/*.plist
case_exit skillcap_default_glob 0 ./scripts/description-cap.sh
case_exit context_budget_real 0 ./scripts/context-budget.sh

# --- the ~/.claude/ link inventory ------------------------------------------
# context-budget.sh caps two files, but seven surfaces are billed, and the gap
# was invisible: skills/, agents/ and loop.md were each linked into ~/.claude/
# with the budget none the wiser, while four docs went on claiming only two
# files were linked at all. The inventory closes that, so it needs the same
# treatment as the gates above — a positive control, a negative control, and a
# refusal to pass when it read nothing.
case_exit inventory_unclassified_link 1 \
  env BOOMFILE=scripts/tests/fixtures/unclassified-link-boomfile.toml ./scripts/context-budget.sh
case_exit inventory_missing_boomfile 1 \
  env BOOMFILE=scripts/tests/fixtures/does-not-exist.toml ./scripts/context-budget.sh

# --- the cap covers SUBAGENTS, not just skills ------------------------------
# dot-claude/agents/ is linked into ~/.claude/ and every agent `description:` is
# billed per session, but the cap read only dot-claude/skills/ — two of the seven
# always-loaded surfaces sat outside the only cap that governs them. This is the
# control that keeps the rename honest.
case_exit descriptioncap_agent_over 1 ./scripts/description-cap.sh scripts/tests/fixtures/agents/over-cap-agent.md
case_exit descriptioncap_agent_real 0 ./scripts/description-cap.sh dot-claude/agents/drift-triage.md

# --- rules must be path-scoped, or they are not free ------------------------
# The rules directory is exempt from the byte ceiling on one condition: every
# rule carries `paths:`, so it loads only when a matching file is read. A rule
# that omits it is billed at launch exactly like CLAUDE.md — silent, and in the
# expensive direction. Without this suite the exemption would be unearned.
case_exit rules_unscoped 1 ./scripts/rules-scoped.sh scripts/tests/fixtures/rules/unscoped.md
case_exit rules_real 0 ./scripts/rules-scoped.sh
case_exit rules_no_rule_inputs 1 ./scripts/rules-scoped.sh README.md
case_exit rules_missing_dir 1 env DIR=dot-claude/does-not-exist ./scripts/rules-scoped.sh

# --- scheduled jobs actually run, and their last run succeeded ---------------
# Three recorded incidents of one shape: boom-verify dead 28 days behind an
# unexpanded `~`; `code reap --push` at 0 successes against 84 failures; `git
# maintenance` pointed at paths that no longer existed, exiting 1 on every fire.
# Each was found by hand. The fixture stands in for launchctl so these assert the
# script rather than whatever this machine happens to be doing today.
FIX=scripts/tests/fixtures/launchctl-print.sh
case_exit schedule_healthy 0 env PRINT_CMD="$FIX" FIXTURE_MODE=healthy ./scripts/schedule-health.sh
case_exit schedule_failing 1 env PRINT_CMD="$FIX" FIXTURE_MODE=failing ./scripts/schedule-health.sh
case_exit schedule_absent 1 env PRINT_CMD="$FIX" FIXTURE_MODE=absent ./scripts/schedule-health.sh
# runs=0 is REPORTED, not failed: a freshly provisioned machine looks identical,
# and a check that is noisy on day one is bypassed by day two.
case_exit schedule_never_ran 0 env PRINT_CMD="$FIX" FIXTURE_MODE=never-ran ./scripts/schedule-health.sh
# No jobs at all must FAIL rather than pass silently — the property this whole
# suite exists to assert.
case_exit schedule_no_jobs 1 \
  env PRINT_CMD="$FIX" LIST_CMD=true LAUNCHD_DIR=scripts/tests/fixtures/no-launchd ./scripts/schedule-health.sh

# --- boomfile srcs exist ----------------------------------------------------
# taplo proves the file parses, which says nothing about whether the ~56 paths it
# names are there. A missing src fails `boom source` partway through, on a real
# machine, after it has already changed things.
case_exit boomsrc_real 0 ./scripts/boomfile-sources.sh
case_exit boomsrc_missing_file 1 ./scripts/boomfile-sources.sh boomfile-does-not-exist.toml
case_exit boomsrc_dangling 1 ./scripts/boomfile-sources.sh scripts/tests/fixtures/dangling-src-boomfile.toml

# --- the generated index is actually current --------------------------------
# A stale index is worse than none: it sends the reader to the wrong place with
# the confidence of a table of contents. `--check` is the whole guarantee that
# the generated file and the headings it indexes cannot drift.
case_exit toc_current 0 ./scripts/decisions-toc.sh --check
case_exit toc_missing_file 2 env FILE=dot-claude/does-not-exist.md ./scripts/decisions-toc.sh --check

# --- a skill body loads in full when the skill fires -------------------------
# Two skills were ~22 KB single files with no references/, about 5,600 tokens
# each on any trigger, mostly inventory the invocation never needed. The body cap
# is what keeps the split from silently growing back.
case_exit skillbody_real 0 ./scripts/description-cap.sh
case_exit skillbody_over 1 \
  env BODY_CAP=5000 ./scripts/description-cap.sh dot-claude/skills/butter-stack/SKILL.md

# --- the cap must be able to SEE a multi-line description --------------------
# A YAML folded block put the indicator (`>-`) on the `description:` line, and
# the single-line parser scored that as one word — so any skill could carry an
# unbounded description past a gate reporting `ok (1 words)`. The cap is this
# script's entire purpose, and that spelling removed it.
case_exit skillcap_folded_over 1 ./scripts/description-cap.sh scripts/tests/fixtures/folded-over-cap-SKILL.md
# Positive control: a SHORT folded block must still pass, or the fix would have
# replaced one broken gate with another.
case_exit skillcap_folded_under 0 ./scripts/description-cap.sh scripts/tests/fixtures/folded-under-cap-SKILL.md

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
