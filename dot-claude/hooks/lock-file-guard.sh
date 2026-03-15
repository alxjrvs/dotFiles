#!/usr/bin/env bash
# PreToolUse hook: block edits to lock files.
# Reads TOOL_INPUT (JSON) from stdin, checks if file_path matches a lock file pattern.
# Exit 2 = block the tool call; Exit 0 = allow.

set -euo pipefail

input=$(cat)

if echo "$input" | grep -qE '(Brewfile\.lock|bun\.lock|package-lock\.json|yarn\.lock|pnpm-lock\.yaml|Gemfile\.lock|Cargo\.lock|composer\.lock)'; then
  echo "BLOCK: Do not edit lock files directly" >&2
  exit 2
fi

exit 0
