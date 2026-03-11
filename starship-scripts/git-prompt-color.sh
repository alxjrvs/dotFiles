#!/bin/sh
# git-prompt-color.sh - Outputs a colored ❯ based on git status severity
# Used by starship-tmux.toml custom.prompt module.
# Colors: red (dirty) > yellow (unpushed) > green (clean) > white (no repo)

fg() { printf '\033[38;2;%d;%d;%dm' "$1" "$2" "$3"; }
rst() { printf '\033[0m'; }

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf '%s❯%s' "$(fg 240 240 240)" "$(rst)"
  exit 0
fi

if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  # Dirty → red
  printf '%s❯%s' "$(fg 224 108 117)" "$(rst)"
  exit 0
fi

if git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1 &&
   git log @{u}.. --oneline 2>/dev/null | grep -q .; then
  # Unpushed → yellow
  printf '%s❯%s' "$(fg 229 192 123)" "$(rst)"
  exit 0
fi

# Clean → green
printf '%s❯%s' "$(fg 152 195 121)" "$(rst)"
