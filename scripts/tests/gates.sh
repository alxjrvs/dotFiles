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
# A positive control matters as much as a negative one — a gate that fails on
# everything is no more useful than one that passes on everything — but only
# where nothing else exercises the happy path. On the REAL inputs, CI and
# lefthook both do, so those positives lived here as a second copy of a check
# that was already running. The ones kept below are fixture-based, or the
# positive half of a fixture-paired block.
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

# --- no STANDALONE positive controls on real inputs --------------------------
# Six are gone. Each ran a script on the same real input that lint.yml already
# runs as its own dedicated step — settings-guardrails on settings.json (:108),
# plist-validity on launchd/*.plist (:120), context-budget (:134),
# boomfile-sources (:161), description-cap over the real skills and agents
# (:167) — and two of them were byte-identical to each other. A failure on real
# input surfaced twice in one job and never once alone; this suite runs INSIDE
# that same job, so it could not even fail earlier.
#
# A positive control earns its place when nothing else exercises the happy path.
# Here everything does: CI on the committed tree, lefthook on the staged one.
#
# What stays, and why it is not the same thing:
#   - FIXTURE positives (`skillcap_folded_under`, `all_passing_suite`). Nothing
#     outside this file ever runs those inputs.
#   - The positive HALF of a fixture-paired block (`rules_real`,
#     `descriptioncap_agent_real`). Deleting those leaves a block that only ever
#     asserts failure, and a gate that fails on everything is no more useful
#     than one that passes on everything — which is this file's opening claim.

# --- the restated-count check must not be written with `\b` -----------------
# git grep's ERE does not implement the word-boundary escape: the pattern
# compiles, matches nothing, and the check reports ok on a file that plainly
# violates it. The first draft of the restated-count gate did exactly that, and
# passed a planted counter-example in README.md. This asserts the shape rather
# than the behaviour, because the check greps the whole repo and has no fixture
# form — and the failure being guarded is that a silent no-op looks identical
# to a pass. Comment lines are excluded: this file and that one both have to be
# able to NAME the escape in order to explain it.
if grep -v '^[[:space:]]*#' scripts/context-budget.sh | grep -q '\\b'; then
  fail=$((fail + 1))
  echo "  [context_budget_no_word_boundary] scripts/context-budget.sh uses the word-boundary escape, which git grep silently ignores"
else
  pass=$((pass + 1))
fi

# --- the project-scoped settings.local.json must be caught -------------------
# `.gitignore` hides this file at every scope, so it can never be committed and
# never be reviewed. `boomfile.toml`'s `absent` resource covers only the
# user-global twin. A real one was found on disk with the assertion missing, and
# the 2026-08-28 incident file carried `Bash(gh api *)` under `defaultMode: auto`.
#
# Driven for real rather than asserted on the source: the file is planted, the
# gate must exit non-zero, and it is removed again. A `trap` does the cleanup so
# a failure between the two does not leave the tree dirty — and the planted file
# is exactly the shape the incident had.
_local=".claude/settings.local.json"
if [ -e "$_local" ]; then
  fail=$((fail + 1))
  echo "  [settings_local_present] $_local exists — delete it before running this suite"
else
  mkdir -p .claude
  printf '{"permissions":{"allow":["Bash(gh api *)"]}}' > "$_local"
  trap 'rm -f "$_local"; rmdir .claude 2> /dev/null || true' EXIT
  case_exit settings_local_caught 1 ./scripts/settings-guardrails.sh dot-claude/settings.json
  rm -f "$_local"
  rmdir .claude 2> /dev/null || true
  trap - EXIT
  # And the positive half: with it gone, the same call must pass again.
  case_exit settings_local_clean 0 ./scripts/settings-guardrails.sh dot-claude/settings.json
fi

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

# --- boomfile srcs exist ----------------------------------------------------
# taplo proves the file parses, which says nothing about whether the paths it
# names are there. A missing src fails `boom source` partway through, on a real
# machine, after it has already changed things.
case_exit boomsrc_missing_file 1 ./scripts/boomfile-sources.sh boomfile-does-not-exist.toml
case_exit boomsrc_dangling 1 ./scripts/boomfile-sources.sh scripts/tests/fixtures/dangling-src-boomfile.toml

# --- a skill body loads in full when the skill fires -------------------------
# Two skills were ~22 KB single files with no references/, about 5,600 tokens
# each on any trigger, mostly inventory the invocation never needed. The body cap
# is what keeps the split from silently growing back.
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
