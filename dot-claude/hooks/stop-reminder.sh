#!/usr/bin/env bash
# Stop hook: remind about uncommitted changes when Claude finishes.
# Exit 0 always — never blocks.

set -uo pipefail

# Only run if we're in a git repo
if git rev-parse --is-inside-work-tree &>/dev/null; then
  if git status --porcelain 2>/dev/null | grep -q .; then
    echo "Uncommitted changes in working directory"
  fi
fi

exit 0
