#!/usr/bin/env bash
# CwdChanged hook: minimal context injection on directory change.
# Only surfaces what Claude can't trivially re-derive: branch/dirty count and
# presence of CLAUDE.md. Other signals (framework, monorepo, docker, package
# manager) are a single Read away and don't need to be eagerly injected.
# Exit 0 always — informational only, never blocks.

set -uo pipefail

input=$(cat)
new_cwd=$(echo "$input" | jq -r '.cwd // empty')

[[ -z "$new_cwd" || ! -d "$new_cwd" ]] && exit 0

signals=()

if git -C "$new_cwd" rev-parse --is-inside-work-tree &>/dev/null; then
  branch=$(git -C "$new_cwd" symbolic-ref --short HEAD 2>/dev/null || echo "detached")
  dirty=$(git -C "$new_cwd" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  signals+=("git: $branch, $dirty uncommitted")
fi

[[ -f "$new_cwd/CLAUDE.md" ]] && signals+=("CLAUDE.md present")

[[ ${#signals[@]} -eq 0 ]] && exit 0

context="cwd: $new_cwd"
for s in "${signals[@]}"; do
  context="$context; $s"
done
jq -n --arg ctx "$context" '{"additionalContext": $ctx}'
exit 0
