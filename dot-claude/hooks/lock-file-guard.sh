#\!/usr/bin/env bash
# PreToolUse hook: block edits to lock files.
# Reads TOOL_INPUT (JSON) from stdin. Extracts the target file_path and matches
# it (the path only, NOT raw JSON content) against the lock-file pattern.
# Exit 2 = block the tool call; Exit 0 = allow.

set -euo pipefail

input=$(cat)
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .file_path // empty' 2>/dev/null || true)

# Empty file_path => not a path-targeted tool call; allow.
[ -z "$file_path" ] && exit 0

# Use the basename so the pattern matches regardless of directory prefix.
base=$(basename "$file_path")

case "$base" in
  Brewfile.lock|Brewfile.lock.json|bun.lock|bun.lockb|package-lock.json|yarn.lock|pnpm-lock.yaml|Gemfile.lock|Cargo.lock|composer.lock|poetry.lock|uv.lock|flake.lock)
    echo "BLOCK: Do not edit lock files directly" >&2
    exit 2
    ;;
esac

exit 0
