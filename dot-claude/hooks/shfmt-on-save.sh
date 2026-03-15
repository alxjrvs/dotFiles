#!/usr/bin/env bash
# PostToolUse hook: auto-format .sh files with shfmt after edit/write.
# Reads TOOL_INPUT (JSON) from stdin, extracts file_path, formats if applicable.
# Exit 0 always — formatting is best-effort.

set -uo pipefail

input=$(cat)

file_path=$(echo "$input" | jq -r '.file_path // empty')

if [[ -n "$file_path" && "$file_path" == *.sh ]] && command -v shfmt &>/dev/null; then
  shfmt -w -i 2 "$file_path" 2>/dev/null || true
fi

exit 0
