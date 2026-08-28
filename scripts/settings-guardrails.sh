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
worktree-checkout-guard.sh
worktree-remove-guard.sh
repo-scope-guard.sh
worktree-freshness.sh
worktree-port.sh
worktree-publish.sh
pr-review.sh
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
DENY
}

fail=0
note() {
  echo "$1"
  fail=1
}

for f in "$@"; do
  [ -f "$f" ] || continue

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
