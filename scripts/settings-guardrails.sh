#!/usr/bin/env sh
# settings.json content guardrails — the single source for the assertions.
#
# Called from three places, deliberately: lefthook's pre-commit (against the
# staged file, so a bad commit is caught immediately), .github/workflows/lint.yml
# (so it holds for anything arriving without a local hook), and boomfile.toml's
# `boom verify` (against the LIVE ~/.claude/settings.json, which is the only copy
# that actually governs a session). Three call sites, one copy of the rules.
#
# Usage: scripts/settings-guardrails.sh <file>...
#
# WHY THIS FILE EXISTS. Until now these assertions were written out three times —
# lefthook.yml, lint.yml and boomfile.toml each carried the full list plus its
# own copy of the reasoning, and two of them carried a comment instructing a
# human to keep the inventory in sync by hand. They had already drifted in form:
# boomfile expressed some checks as declarative `[[section.check]]` resources
# while the other two grepped for the same thing.
#
# DECISIONS.md diagnosed this exact class for the context ceilings and the
# diagnosis applies unchanged here: "both copies are executable, so both look
# authoritative, and neither is wrong until the day they differ." This is that
# prescription applied a second time. scripts/context-budget.sh is the model.
#
# WHY THE HOOK LIST IS THE WHOLE LIST. The previous assertion greped for
# `op-guard.sh` and nothing else, so deleting the `rebase-guard.sh` or
# `worktree-checkout-guard.sh` handler passed lefthook, CI *and* `boom verify`
# green — the scripts still on disk, still linked, still passing their suites,
# and enforcing nothing. A guard that can be silently un-wired is not a control.
# Adding a hook to settings.json without adding it here is how this stops
# applying, exactly as context-budget.sh warns about its own capped set.
set -eu

# Hook scripts that must be wired. One name per line, no comments inline.
wired_hooks() {
  cat << 'HOOKS'
op-guard.sh
rebase-guard.sh
worktree-remove-guard.sh
repo-scope-guard.sh
worktree-freshness.sh
worktree-port.sh
verify-gate.sh
HOOKS
}

# The secret-path deny floor: the Bash path to a *resolved* secret, not just to
# `op`. `op-agent header` and `op-agent git-credential get` each print a live
# credential to stdout, and stdout is model context — `op-agent header` is the
# command that leaked a PAT into a transcript.
#
# ARRAY-AWARE, never a substring grep. The original form asked only whether a
# string appeared anywhere in the file, so moving an entry from `deny` into
# `allow` inverted the control with every gate still green. `jq index` asserts
# membership of the deny ARRAY, and passing the value through --arg means it is
# data rather than a pattern — which also sidesteps the metacharacters that made
# `grep -F` necessary before.
#
# EVERY entry, not a chosen few: an earlier list asserted the `op`/`op-agent`/
# `git credential` shapes only, so the keychain read and both `Read()` rules
# could be deleted unnoticed.
deny_floor() {
  cat << 'DENY'
Bash(security find-generic-password:*)
Bash(op read:*)
Bash(op item get:*)
Bash(op document get:*)
Bash(op-agent:*)
Bash(~/.local/bin/op-agent:*)
Bash(git credential:*)
Read(~/.ssh/id_*)
Read(~/.aws/credentials)
Bash(*/op *)
Bash(*/op-agent *)
Bash(boom askpass:*)
Bash(*/boom askpass *)
Bash(*/security find-generic-password *)
Bash(*/security find-internet-password *)
Bash(*/security find-certificate *)
Bash(*/security find-identity *)
Bash(*/git credential *)
Bash(*/git credential-store *)
Bash(*/git credential-cache *)
DENY
}

fail=0
note() {
  echo "$1"
  fail=1
}

# A gate that asserts nothing must never print `ok`. Called with a path that
# does not exist, this printed `ok settings guardrails (…)` and exited 0 — and
# CI hands it a literal path, so renaming the settings file would have left the
# required `lint` check green while the deny floor went unchecked. That is the
# incident already recorded in DECISIONS.md: "scripts on disk, linked, suites
# passing, enforcing nothing."
[ "$#" -gt 0 ] || {
  echo "no inputs — the caller's glob matched nothing, so nothing was checked" >&2
  exit 1
}

# The wired_hooks() list is hand-maintained, and a guard MISSING from it is
# invisible: this gate would pass while the new guard sat unwired in settings.json.
# That is the same "scripts on disk, linked, suites passing, enforcing nothing"
# shape the list itself was added to prevent, one level up — applied to the list
# rather than to the handlers. Asserted here so the two can never drift.
#
# Repo-relative, and SKIPPED when the repo is not adjacent: this script also runs
# from `boom verify` against the live ~/.claude/settings.json, and a missing
# checkout there must not fail the gate. The assertion is about repo contents, so
# it only means anything where the repo is.
#
# GUARD_DIR is overridable so scripts/tests/gates.sh can aim this at a fixture
# and prove the assertion actually fires; it defaults to this repo's own guards.
_guard_dir=${GUARD_DIR:-$(
  unset CDPATH
  cd -- "$(dirname -- "$0")/../dot-claude/hooks" 2> /dev/null && pwd
)}
if [ -n "$_guard_dir" ]; then
  for _g in "$_guard_dir"/*.sh; do
    [ -f "$_g" ] || continue
    _n=${_g##*/}
    # guard-lib.sh is sourced by the others, never wired as a handler itself.
    if [ "$_n" != "guard-lib.sh" ]; then
      wired_hooks | grep -qxF "$_n" || note "$_n is in dot-claude/hooks/ but not in wired_hooks() — add it there, or settings.json can drop its handler with every gate still green"
    fi
  done
fi

for f in "$@"; do
  [ -f "$f" ] || {
    note "$f: expected settings file is missing"
    continue
  }

  jq -e . "$f" > /dev/null || {
    note "$f: not valid JSON"
    continue
  }

  # An auto-approved MCP server is a tool surface nobody reviewed.
  ! grep -qE '(enableAllProjectMcpServers|enabledMcpjsonServers)' "$f" ||
    note "$f: forbidden auto-approve MCP key"

  # The agent's git credentials must come from op-agent, never a cached PAT.
  grep -q 'op-agent git-credential' "$f" ||
    note "$f: agent git helper not wired to op-agent git-credential"
  ! grep -q 'osxkeychain' "$f" ||
    note "$f: forbidden osxkeychain git helper (cached-PAT regression)"

  ! grep -qE '"model"[[:space:]]*:[[:space:]]*"[^"]*fable' "$f" ||
    note "$f: Fable pinned as default model"

  # Every guard must still be wired. `permissions.allow` pre-approves
  # `Bash(op run:*)`, and op-guard is what strips the unsafe variants of that
  # shape before the permission system sees it — un-wiring a hook while leaving
  # the allow entry is the one edit that silently converts this config from
  # "narrower" into "wider".
  wired_hooks | while IFS= read -r h; do
    [ -n "$h" ] || continue
    grep -q "$h" "$f" || {
      echo "$f: hook $h is not wired, but its guarantees are assumed elsewhere"
      exit 1
    }
  done || fail=1

  # A guard's `if` must be a SUBSTRING rule, never program position. A Bash rule
  # matches the whole command text, so `Bash(git *)` misses every spelling the
  # guards were extended to resolve — `/usr/bin/git push`, `sudo git push`,
  # `env git push`, `(git push …)`, `bash -c "git push origin main"`. Each of
  # those is an existing `deny` case in cases.tsv, and each skipped its guard
  # entirely while the suite stayed green, because the suite calls the guard
  # scripts directly and never reads this file. Over-firing costs one process;
  # under-firing costs the default branch. See DECISIONS.md.
  bad_if=$(jq -r '
    [ .hooks.PreToolUse[]?.hooks[]?
      | select(.command | test("hooks/(rebase|worktree-checkout|worktree-remove|repo-scope)-guard\\.sh"))
      | select(has("if"))
      | select(.["if"] | test("^Bash\\(\\*.*\\*\\)$") | not)
      | "\(.command) -> \(.["if"])"
    ] | .[]' "$f" 2> /dev/null)
  [ -z "$bad_if" ] || note "$f: guard \`if\` rule is not the substring form (Bash(*…*)): $bad_if"

  deny_floor | while IFS= read -r d; do
    [ -n "$d" ] || continue
    jq -e --arg d "$d" '.permissions.deny | index($d)' "$f" > /dev/null || {
      echo "$f: missing deny entry $d in .permissions.deny (secret-path floor)"
      exit 1
    }
  done || fail=1
done

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "settings.json is the only thing standing between an unattended session"
  echo "and a resolved secret. Restore the assertion rather than relaxing it."
  exit 1
fi

echo "ok settings guardrails ($*)"
