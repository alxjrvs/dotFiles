#!/bin/sh
# git-prompt-color.sh - Outputs color code for git status severity
# Used by starship-tmux.toml to color the prompt character.
# Output: hex color code (red > yellow > green > white)

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "white"
  exit 0
fi

# Dirty working tree → red (most severe)
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  echo "#e06c75"
  exit 0
fi

# Unpushed commits → yellow
if git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1 &&
   git log @{u}.. --oneline 2>/dev/null | grep -q .; then
  echo "#e5c07b"
  exit 0
fi

# Clean → green
echo "#98c379"
