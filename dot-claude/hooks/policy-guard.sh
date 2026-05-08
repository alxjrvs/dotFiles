#!/usr/bin/env bash
# PreToolUse hook: block hook-bypass and other policy violations on Bash commands.
# Exits 2 with stderr to deny execution; exits 0 to allow.

set -uo pipefail

input=$(cat)

tool_name=$(printf '%s' "$input" | jq -r '.tool_name // empty')
[[ "$tool_name" != "Bash" ]] && exit 0

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
[[ -z "$cmd" ]] && exit 0

# --no-verify on git commit/push bypasses pre-commit/pre-push hooks.
# Match either "--no-verify" or short "-n" used with commit/push (avoid false-positives on `git log -n`).
if printf '%s' "$cmd" | grep -qE '\bgit\s+(commit|push|merge|rebase|cherry-pick|am|notes)\b.*--no-verify\b'; then
  echo "BLOCKED by policy-guard: --no-verify bypasses pre-commit/pre-push hooks (forbidden by user policy)." >&2
  exit 2
fi

# --no-gpg-sign disables signing without explicit user request.
if printf '%s' "$cmd" | grep -qE '\bgit\s+\S+.*--no-gpg-sign\b'; then
  echo "BLOCKED by policy-guard: --no-gpg-sign disables commit signing without authorization." >&2
  exit 2
fi

# Force-with-lease and force pushes already filtered by permissions.deny; this catches the env/sudo wrapper case.
if printf '%s' "$cmd" | grep -qE '\bgit\s+push\b.*(--force[^-]|-f\b)' \
  && ! printf '%s' "$cmd" | grep -qE '\-\-force-with-lease\b'; then
  echo "BLOCKED by policy-guard: 'git push --force' is forbidden; use --force-with-lease." >&2
  exit 2
fi

# Deletion of base branches of open PRs is hard to detect without API calls; warn on suspicious patterns.
if printf '%s' "$cmd" | grep -qE '\bgit\s+(branch|push)\b.*(\-D|\-\-delete|:[a-z])'; then
  # Allow but emit additional context so Claude reflects before continuing.
  jq -n '{additionalContext: "policy-guard: branch-deletion command detected. Verify no open PRs depend on this branch (use `gh pr list --base <branch>`) before proceeding."}'
fi

exit 0
