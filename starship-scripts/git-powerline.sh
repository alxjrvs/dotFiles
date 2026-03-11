#!/bin/sh
# git-powerline.sh - Outputs complete git powerline segment for starship
# Replaces 12 custom modules with a single subprocess.
# Uses ANSI 24-bit color escape codes for styling.
# Colors: Nova palette (theme.sh)

# shellcheck source=../theme.sh
. "$HOME/dotFiles/theme.sh"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

branch=$(git branch --show-current 2>/dev/null)
[ -z "$branch" ] && branch=$(git rev-parse --short HEAD 2>/dev/null)
[ -z "$branch" ] && exit 0

porcelain=$(git status --porcelain 2>/dev/null)
has_dirty=0; [ -n "$porcelain" ] && has_dirty=1
has_stash=0; git stash list 2>/dev/null | grep -q . && has_stash=1
has_unpushed=0
if git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
  git log @{u}.. --oneline 2>/dev/null | grep -q . && has_unpushed=1
fi

# Colors — Nova palette aliases
GRAY_R=$NOVA_BRANCH_R;    GRAY_G=$NOVA_BRANCH_G;    GRAY_B=$NOVA_BRANCH_B
BLUE_R=$NOVA_GIT_BLUE_R;  BLUE_G=$NOVA_GIT_BLUE_G;  BLUE_B=$NOVA_GIT_BLUE_B
RED_R=$NOVA_GIT_RED_R;    RED_G=$NOVA_GIT_RED_G;    RED_B=$NOVA_GIT_RED_B
YEL_R=$NOVA_GIT_YELLOW_R; YEL_G=$NOVA_GIT_YELLOW_G; YEL_B=$NOVA_GIT_YELLOW_B
GRN_R=$NOVA_GIT_GREEN_R;  GRN_G=$NOVA_GIT_GREEN_G;  GRN_B=$NOVA_GIT_GREEN_B
BG_R=$NOVA_BG_R;          BG_G=$NOVA_BG_G;          BG_B=$NOVA_BG_B
WH_R=$NOVA_FG_R;          WH_G=$NOVA_FG_G;          WH_B=$NOVA_FG_B

# ANSI helpers
fg() { printf '\033[38;2;%d;%d;%dm' "$1" "$2" "$3"; }
bg() { printf '\033[48;2;%d;%d;%dm' "$1" "$2" "$3"; }
rst() { printf '\033[0m'; }

# Powerline glyph
A=""

# Determine the status color
if [ "$has_dirty" = "1" ]; then
  S_R=$RED_R; S_G=$RED_G; S_B=$RED_B
elif [ "$has_unpushed" = "1" ]; then
  S_R=$YEL_R; S_G=$YEL_G; S_B=$YEL_B
else
  S_R=$GRN_R; S_G=$GRN_G; S_B=$GRN_B
fi

# Build output
o=""

# Opening arrow: terminal bg -> gray
o="${o}$(bg $GRAY_R $GRAY_G $GRAY_B)$(fg $BG_R $BG_G $BG_B)${A}"
# Branch text on gray
o="${o}$(bg $GRAY_R $GRAY_G $GRAY_B)$(fg $WH_R $WH_G $WH_B)  ${branch} "

if [ "$has_stash" = "1" ]; then
  # Arrow: gray -> blue
  o="${o}$(bg $BLUE_R $BLUE_G $BLUE_B)$(fg $GRAY_R $GRAY_G $GRAY_B)${A}"
  # Arrow: blue -> status color
  o="${o}$(bg $S_R $S_G $S_B)$(fg $BLUE_R $BLUE_G $BLUE_B)${A}"
elif [ "$has_dirty" = "1" ] && [ "$has_unpushed" = "1" ]; then
  # Arrow: gray -> red
  o="${o}$(bg $RED_R $RED_G $RED_B)$(fg $GRAY_R $GRAY_G $GRAY_B)${A}"
  # Arrow: red -> yellow
  o="${o}$(bg $YEL_R $YEL_G $YEL_B)$(fg $RED_R $RED_G $RED_B)${A}"
  # Closing arrow: yellow -> terminal
  o="${o}$(rst)$(fg $YEL_R $YEL_G $YEL_B)${A}$(rst)"
  printf '%s' "$o"
  exit 0
else
  # Arrow: gray -> status color
  o="${o}$(bg $S_R $S_G $S_B)$(fg $GRAY_R $GRAY_G $GRAY_B)${A}"
fi

if [ "$has_stash" = "1" ] && [ "$has_dirty" = "1" ] && [ "$has_unpushed" = "1" ]; then
  # stash+dirty+unpushed: blue -> red -> yellow -> close
  # (blue->red already rendered, now red->yellow)
  o="${o}$(bg $YEL_R $YEL_G $YEL_B)$(fg $RED_R $RED_G $RED_B)${A}"
  o="${o}$(rst)$(fg $YEL_R $YEL_G $YEL_B)${A}$(rst)"
  printf '%s' "$o"
  exit 0
elif [ "$has_stash" = "1" ] && [ "$has_dirty" = "1" ] && [ "$has_unpushed" = "0" ]; then
  # stash+dirty: blue -> red -> close
  o="${o}$(rst)$(fg $RED_R $RED_G $RED_B)${A}$(rst)"
  printf '%s' "$o"
  exit 0
elif [ "$has_stash" = "1" ] && [ "$has_dirty" = "0" ] && [ "$has_unpushed" = "1" ]; then
  # stash+unpushed: blue -> yellow -> close
  o="${o}$(rst)$(fg $YEL_R $YEL_G $YEL_B)${A}$(rst)"
  printf '%s' "$o"
  exit 0
fi

# Simple cases: closing arrow from status color
o="${o}$(rst)$(fg $S_R $S_G $S_B)${A}$(rst)"
printf '%s' "$o"
