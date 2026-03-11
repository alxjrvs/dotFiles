#!/bin/sh
# git-prompt-color.sh - Outputs a colored ❯ based on git status severity
# Used by starship-tmux.toml custom.prompt module.
# Colors: Nova palette (theme.sh) — red (dirty) > yellow (unpushed) > green (clean) > white (no repo)

# shellcheck source=../theme.sh
. "$HOME/dotFiles/theme.sh"

fg() { printf '\033[38;2;%d;%d;%dm' "$1" "$2" "$3"; }
rst() { printf '\033[0m'; }

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf '%s❯%s' "$(fg $NOVA_FG_R $NOVA_FG_G $NOVA_FG_B)" "$(rst)"
  exit 0
fi

if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  # Dirty → red
  printf '%s❯%s' "$(fg $NOVA_GIT_RED_R $NOVA_GIT_RED_G $NOVA_GIT_RED_B)" "$(rst)"
  exit 0
fi

if git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1 &&
   git log @{u}.. --oneline 2>/dev/null | grep -q .; then
  # Unpushed → yellow
  printf '%s❯%s' "$(fg $NOVA_GIT_YELLOW_R $NOVA_GIT_YELLOW_G $NOVA_GIT_YELLOW_B)" "$(rst)"
  exit 0
fi

# Clean → green
printf '%s❯%s' "$(fg $NOVA_GIT_GREEN_R $NOVA_GIT_GREEN_G $NOVA_GIT_GREEN_B)" "$(rst)"
