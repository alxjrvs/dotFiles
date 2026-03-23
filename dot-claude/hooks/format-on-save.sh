#!/usr/bin/env bash
# PostToolUse hook: auto-format files after edit/write.
# Reads TOOL_INPUT (JSON) from stdin, extracts file_path, routes by extension.
# Exit 0 always — formatting is best-effort.

set -uo pipefail

input=$(cat)

file_path=$(echo "$input" | jq -r '.file_path // empty')

[[ -z "$file_path" ]] && exit 0

case "$file_path" in
  *.sh)
    command -v shfmt &>/dev/null && shfmt -w -i 2 "$file_path" 2>/dev/null || true
    ;;
  *.ts | *.tsx | *.js | *.jsx | *.css | *.json | *.md | *.mdx)
    command -v prettier &>/dev/null && prettier --write "$file_path" 2>/dev/null || true
    ;;
esac

exit 0
