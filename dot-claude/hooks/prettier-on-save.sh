#!/usr/bin/env bash
# PostToolUse hook: auto-format JS/TS/CSS/JSON files with Prettier after edit/write.
# Reads TOOL_INPUT (JSON) from stdin, extracts file_path, formats if applicable.
# Exit 0 always — formatting is best-effort.

set -uo pipefail

input=$(cat)

file_path=$(echo "$input" | jq -r '.file_path // empty')

if [[ -n "$file_path" && "$file_path" =~ \.(ts|tsx|js|jsx|css|json|md|mdx)$ ]] && command -v prettier &>/dev/null; then
  prettier --write "$file_path" 2>/dev/null || true
fi

exit 0
