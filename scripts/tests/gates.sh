#!/usr/bin/env bash
# Regression suite for the shared assertion scripts in `scripts/`.
#
# Every case here asserts the SAME property: a gate that checked nothing must not
# print `ok` and must not exit 0. Callers hand these scripts a literal path, or a
# glob expansion that can be empty, so renaming a settings file or moving
# `home/Library/LaunchAgents/` must not leave the required `lint` check green with the deny floor
# and the launchd `~` bug unchecked.
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
case_exit guardrails_missing_path 1 ./scripts/settings-guardrails.sh home/dot_claude/does-not-exist.json
case_exit plist_missing_path 1 ./scripts/plist-validity.sh home/Library/LaunchAgents/does-not-exist.plist

# --- an EMPTY input list must FAIL: the caller's glob matched nothing --------
case_exit guardrails_no_args 1 ./scripts/settings-guardrails.sh
case_exit plist_no_args 1 ./scripts/plist-validity.sh

# A guard on disk that wired_hooks() does not name must FAIL. Without this, the
# hand-maintained list silently stops covering a new guard and settings.json
# could drop that handler with every gate still green. The fixture directory
# holds a single deliberately-unnamed guard.
case_exit guardrails_unwired_guard 1 \
  env GUARD_DIR=scripts/tests/fixtures/hooks ./scripts/settings-guardrails.sh home/dot_claude/settings.json

# --- positive controls: the real inputs must still PASS ----------------------
case_exit guardrails_real 0 ./scripts/settings-guardrails.sh home/dot_claude/settings.json
# Globbed, not named: a hardcoded plist label is an owner this suite would
# carry into every fork.
case_exit plist_real 0 ./scripts/plist-validity.sh home/Library/LaunchAgents/*.plist

# --- the project-scoped settings.local.json must be caught -------------------
# `.gitignore` hides this file at every scope, so it can never be committed and
# never be reviewed, and `home/.chezmoiremove` covers only the
# user-global twin.
#
# Driven for real rather than asserted on the source: the file is planted, the
# gate must exit non-zero, and it is removed again. A `trap` does the cleanup so
# a failure between the two does not leave the tree dirty.
_local=".claude/settings.local.json"
if [ -e "$_local" ]; then
  fail=$((fail + 1))
  echo "  [settings_local_present] $_local exists — delete it before running this suite"
else
  mkdir -p .claude
  printf '{"permissions":{"allow":["Bash(gh api *)"]}}' > "$_local"
  trap 'rm -f "$_local"; rmdir .claude 2> /dev/null || true' EXIT
  case_exit settings_local_caught 1 ./scripts/settings-guardrails.sh home/dot_claude/settings.json
  rm -f "$_local"
  rmdir .claude 2> /dev/null || true
  trap - EXIT
  # And the positive half: with it gone, the same call must pass again.
  case_exit settings_local_clean 0 ./scripts/settings-guardrails.sh home/dot_claude/settings.json
fi

# --- a third-party tap must declare its trust, with or without brew ---------
# brew-drift.sh's tap-trust assertion reads the Brewfile, not the machine, so it
# must fire on a runner too — it did not, once: the `command -v brew` early exit
# sat above it, and the regression it exists for sailed through CI. Negative
# control only: a fixture Brewfile is a wrong declared list on any real machine.
case_exit brewdrift_untrusted_tap 1 ./scripts/brew-drift.sh scripts/tests/fixtures/untrusted-tap-Brewfile

# --- the gitleaks .mcp.json rule fires on the bare placeholder --------------
# gitleaks' default global allowlist drops any finding that is exactly `${NAME}`,
# which is the shape this rule exists for; the first spelling of the rule was
# silently allowlisted on every real case. The fixture is generated, never
# tracked, so CI's own `gitleaks dir .` does not trip over it.
if command -v gitleaks > /dev/null 2>&1; then
  _gl=$(mktemp -d)
  # shellcheck disable=SC2016  # the literal ${GITHUB_TOKEN} IS the fixture
  printf '{"mcpServers":{"github":{"env":{"GITHUB_TOKEN":"${GITHUB_TOKEN}"}}}}\n' > "$_gl/.mcp.json"
  case_exit gitleaks_mcp_placeholder_caught 1 gitleaks dir "$_gl" --config gitleaks/gitleaks.toml --no-banner --redact
  printf '{"mcpServers":{"github":{"command":"op","args":["run","--env-file=.env","--","srv"]}}}\n' > "$_gl/.mcp.json"
  case_exit gitleaks_mcp_clean_ok 0 gitleaks dir "$_gl" --config gitleaks/gitleaks.toml --no-banner --redact
  rm -rf "$_gl"
else
  echo "  [gitleaks_mcp_*] skipped: gitleaks not on PATH (CI has it)"
fi

# --- the sandbox's two measured invariants ----------------------------------
# DERIVED FROM THE REAL FILE, never a checked-in fixture: a fixture copy of
# settings.json drifts from the original the moment either changes, and then
# these cases prove something about a file nobody ships. `jq` mutates the live
# one into each defect, so the input is always current.
_sbox=$(mktemp -d)
trap 'rm -rf "$_sbox"' EXIT

# `credentials.files` is measured (2026-08-18) to break op-agent — it removes
# login.keychain-db from the search list, so the securityd IPC never resolves.
# It is also the first thing the vendor example shows, which is why it needs a
# gate and not a paragraph.
jq '.sandbox.credentials.files = [{"path":"~/.ssh","mode":"deny"}]' \
  home/dot_claude/settings.json > "$_sbox/credfiles.json"
case_exit sandbox_credfiles_caught 1 ./scripts/settings-guardrails.sh "$_sbox/credfiles.json"

# A `sandbox` block present with `enabled` anything but `true` binds to nothing.
# This exact shape shipped once: a null `enabled` under ten credential and path
# rules that read as a posture and enforced nothing. Both spellings of the
# defect — explicitly null, and the key absent — must be caught.
jq '.sandbox.enabled = null' home/dot_claude/settings.json > "$_sbox/null.json"
case_exit sandbox_enabled_null_caught 1 ./scripts/settings-guardrails.sh "$_sbox/null.json"
jq 'del(.sandbox.enabled)' home/dot_claude/settings.json > "$_sbox/missing.json"
case_exit sandbox_enabled_absent_caught 1 ./scripts/settings-guardrails.sh "$_sbox/missing.json"

# Positive control: NO sandbox block at all is a legitimate state (it is what
# this file held yesterday), so the `enabled` assertion must not fire on it.
# Without this the gate would forbid ever turning the sandbox back off.
jq 'del(.sandbox)' home/dot_claude/settings.json > "$_sbox/none.json"
case_exit sandbox_absent_ok 0 ./scripts/settings-guardrails.sh "$_sbox/none.json"

rm -rf "$_sbox"
trap - EXIT

if [ "$fail" -gt 0 ]; then
  echo "gate-tests: $pass passed, $fail FAILED"
  exit 1
fi
echo "gate-tests: $pass passed"
