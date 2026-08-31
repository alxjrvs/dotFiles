#!/usr/bin/env sh
# settings.json content guardrails — the single source for the assertions.
#
# Called from lefthook's pre-commit (the staged file), lint.yml (anything
# arriving without a local hook), and boomfile.toml's `boom verify` (the LIVE
# ~/.claude/settings.json, the only copy that governs a session). Three call
# sites, one copy of the rules.
#
# Usage: scripts/settings-guardrails.sh <file>...
#
# WHY THE HOOK LIST IS THE WHOLE LIST, not a spot-check of one guard: a handler
# that can be deleted with every gate still green leaves the script on disk,
# linked, passing its suite, and enforcing nothing.
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
# credential to stdout, and stdout is model context.
#
# ARRAY-AWARE, never a substring grep: a substring test only asks whether the
# string appears anywhere in the file, so moving an entry from `deny` into
# `allow` inverts the control with every gate green. `jq index` asserts
# membership of the deny ARRAY; --arg passes the value as data, not a pattern.
# EVERY entry — anything left out can be deleted unnoticed.
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

# A gate that asserts nothing must never print `ok`. CI hands this a literal
# path, so renaming the settings file must not leave the required `lint` check
# green with the deny floor unchecked.
[ "$#" -gt 0 ] || {
  echo "no inputs — the caller's glob matched nothing, so nothing was checked" >&2
  exit 1
}

# The wired_hooks() list is hand-maintained, and a guard MISSING from it is
# invisible: this gate would pass while the new guard sat unwired. Repo-relative,
# and SKIPPED when the repo is not adjacent — this also runs from `boom verify`
# against the live settings.json, where a missing checkout must not fail the
# gate. GUARD_DIR is overridable so scripts/tests/gates.sh can aim it at a
# fixture and prove the assertion fires.
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
  # `Bash(op run:*)` and op-guard strips the unsafe variants before the
  # permission system sees it — un-wiring it while leaving the allow entry is the
  # one edit that silently widens this config.
  wired_hooks | while IFS= read -r h; do
    [ -n "$h" ] || continue
    grep -q "$h" "$f" || {
      echo "$f: hook $h is not wired, but its guarantees are assumed elsewhere"
      exit 1
    }
  done || fail=1

  # A guard's `if` must be a SUBSTRING rule, never program position: a Bash rule
  # matches the whole command text, so `Bash(git *)` misses `/usr/bin/git push`,
  # `sudo git push`, `env git push`, `(git push …)`, `bash -c "git push …"`. The
  # suites call the guards directly and never read this file, so only this
  # catches it. Over-firing costs one process; under-firing costs the branch.
  bad_if=$(jq -r '
    [ .hooks.PreToolUse[]?.hooks[]?
      | select(.command | test("hooks/(rebase|worktree-remove|repo-scope)-guard\\.sh"))
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

# THE SAME RULE, ONE SCOPE OVER. `boomfile.toml`'s `absent` resource covers only
# the user-global `~/.claude/settings.local.json`, and `.gitignore` hides the
# file at EVERY scope — so this repo's own project-scoped copy is never
# committable, never reviewable, and asserted by nothing.
#
# It cannot be closed where its sibling is: boom's `absent` runs `expandTilde`
# and nothing else, so a repo-relative path resolves against whatever directory
# boom ran in, and a `~`-anchored path to a development clone is host detection.
# Hence here, resolved from this script's own location rather than `$PWD`, so it
# means the same thing from any working directory.
_repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
_local_settings="$_repo_root/.claude/settings.local.json"
if [ -e "$_local_settings" ]; then
  note "$_local_settings: machine-local override is not a pattern this setup uses (project scope) — delete it; every divergence lives in the committed settings.json"
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "settings.json is the only thing standing between an unattended session"
  echo "and a resolved secret. Restore the assertion rather than relaxing it."
  exit 1
fi

echo "ok settings guardrails ($*)"
