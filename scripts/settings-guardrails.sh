#!/usr/bin/env sh
# settings.json content guardrails — the single source for the assertions.
#
# Called from lefthook's pre-commit (the staged file; CI runs the same roster
# with `--all-files`) and from scripts/verify.sh (the LIVE ~/.claude/settings.json,
# the only copy that governs a session). Two call paths, one copy of the rules.
#
# Usage: scripts/settings-guardrails.sh <file>...
#
# THE HOOK LIST IS READ FROM THE DIRECTORY, never hand-written. The hazard is a
# script on disk with no handler: linked, passing its suite, enforcing nothing.
# A list someone has to remember to extend is the one that stops covering the
# newest guard; a list derived from `ls` cannot be forgotten.
set -eu

# Every hook script beside this repo's settings.json, by basename. guard-lib.sh
# is sourced by the others, never wired as a handler itself.
_hooks_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/../home/dot_claude/hooks" 2> /dev/null && pwd)
wired_hooks() {
  for _g in "$_hooks_dir"/*.sh; do
    [ -f "$_g" ] || continue
    _n=${_g##*/}
    [ "$_n" != guard-lib.sh ] || continue
    printf '%s\n' "$_n"
  done
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

# A gate that asserts nothing must never print `ok`: renaming the settings file
# must not leave the required `lint` check green with the deny floor unchecked.
[ "$#" -gt 0 ] || {
  echo "no inputs — the caller's glob matched nothing, so nothing was checked" >&2
  exit 1
}

# An empty derived list would assert nothing about hooks and still print `ok`;
# every caller (lefthook, CI, scripts/verify.sh) runs this from the checkout.
[ -n "$(wired_hooks)" ] || {
  echo "no hook scripts found in home/dot_claude/hooks — nothing was asserted" >&2
  exit 1
}

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
      | select(.command | test("hooks/(worktree-remove|repo-scope)-guard\\.sh"))
      | select(has("if"))
      | select(.["if"] | test("^Bash\\(\\*.*\\*\\)$") | not)
      | "\(.command) -> \(.["if"])"
    ] | .[]' "$f" 2> /dev/null)
  [ -z "$bad_if" ] || note "$f: guard \`if\` rule is not the substring form (Bash(*…*)): $bad_if"

  # THE SANDBOX'S TWO MEASURED INVARIANTS. Both are re-adoption guards: each
  # names a change that looks correct in the vendor documentation and is wrong
  # HERE, which is exactly the class DECISIONS.md records and nothing else
  # catches.
  #
  # 1. `credentials.files` is measured to break op-agent (2026-08-18): with
  #    keychain file reads denied, `login.keychain-db` leaves the search list
  #    and the securityd IPC never resolves. The published example for this key
  #    lists `~/.ssh` and `~/.aws/credentials` — both already covered here by
  #    `Read()` denials, which the client merges into the sandbox anyway — so
  #    the tempting copy-paste buys nothing and costs the credential helper.
  ! jq -e '.sandbox.credentials.files' "$f" > /dev/null 2>&1 ||
    note "$f: sandbox.credentials.files is set — measured 2026-08-18 to break op-agent by removing login.keychain-db from the search list. The Read() denials already reach the sandbox."

  # 2. A `sandbox` block whose `enabled` is anything but `true` is the exact
  #    defect that shipped once already: six credential denials and four
  #    denyRead paths sat in this file reading as a posture while
  #    `sandbox.enabled` was null, so the whole block bound to nothing. A block
  #    present and off is worse than no block — it is a control that describes
  #    itself. Delete it or turn it on.
  if jq -e 'has("sandbox")' "$f" > /dev/null 2>&1; then
    [ "$(jq -r '.sandbox.enabled' "$f" 2> /dev/null)" = "true" ] ||
      note "$f: a sandbox block is present but sandbox.enabled is not true — it binds to nothing. Delete the block or enable it."
  fi

  deny_floor | while IFS= read -r d; do
    [ -n "$d" ] || continue
    jq -e --arg d "$d" '.permissions.deny | index($d)' "$f" > /dev/null || {
      echo "$f: missing deny entry $d in .permissions.deny (secret-path floor)"
      exit 1
    }
  done || fail=1
done

# THE SAME RULE, ONE SCOPE OVER. `home/.chezmoiremove` covers only the user-global
# `~/.claude/settings.local.json`, and `.gitignore` hides the file at EVERY scope —
# so this repo's own project-scoped copy is never committable, never reviewable,
# and asserted by nothing.
#
# It cannot be closed where its sibling is: `.chezmoiremove` takes target paths
# under ~, and a `~`-anchored path to a development clone is host detection.
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
