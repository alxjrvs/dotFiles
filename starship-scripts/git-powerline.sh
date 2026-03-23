#!/bin/sh
# git-powerline.sh — Git powerline segment for starship
# Renders: [branch pill][status pips...] with seamless powerline transitions.
# Pip order: stash  conflict  staged  unstaged  untracked  ahead  behind
# If none active: single clean pip with ✓
# Colors: Nova palette (theme.sh)

# shellcheck source=../theme.sh
. "$HOME/dotFiles/theme.sh"

# Source git data cache
bash "$HOME/dotFiles/starship-scripts/git-data.sh"
# shellcheck disable=SC1090
. "/tmp/git-data-cache-$(id -u).sh"

if [ -z "$GIT_IS_REPO" ]; then
  branch="-"
  no_git=1
else
  branch="$GIT_BRANCH"
  [ -z "$branch" ] && exit 0

  stash_count="$GIT_STASH_COUNT"
  conflict_count="$GIT_CONFLICT_COUNT"
  staged_count="$GIT_STAGED_COUNT"
  unstaged_count="$GIT_UNSTAGED_COUNT"
  untracked_count="$GIT_UNTRACKED_COUNT"
  ahead="$GIT_AHEAD"
  behind="$GIT_BEHIND"
fi

# ── Colors (RGB triplets) ──────────────────────────────────────────────────
BG_R=$NOVA_BG_R;     BG_G=$NOVA_BG_G;     BG_B=$NOVA_BG_B
BR_R=$NOVA_BRANCH_R; BR_G=$NOVA_BRANCH_G; BR_B=$NOVA_BRANCH_B

# ANSI helpers
fg() { printf '\033[38;2;%d;%d;%dm' "$1" "$2" "$3"; }
bg() { printf '\033[48;2;%d;%d;%dm' "$1" "$2" "$3"; }
rst() { printf '\033[0m'; }

# Powerline glyph
A=""

# ── Branch pill ────────────────────────────────────────────────────────────
o=""
# Opening arrow: segment bg (Nord2 #434C5E) -> branch bg (Nord4 #D8DEE9)
o="${o}$(bg 67 76 94) $(bg $BR_R $BR_G $BR_B)$(fg 67 76 94)${A}"
# Branch text (dark on light)
o="${o}$(bg $BR_R $BR_G $BR_B)$(fg $BG_R $BG_G $BG_B) ${branch} "

# No git repo — close branch pill
if [ "${no_git:-0}" = "1" ]; then
  o="${o}$(rst)$(fg $BR_R $BR_G $BR_B)${A}$(rst)"
  printf '%s' "$o"
  exit 0
fi

# ── Worktree indicator (only when STATUSLINE_WORKTREE is set) ─────────────
if [ -n "$STATUSLINE_WORKTREE" ]; then
  WT_R=$NOVA_WORKTREE_R; WT_G=$NOVA_WORKTREE_G; WT_B=$NOVA_WORKTREE_B
  o="${o}$(bg $WT_R $WT_G $WT_B)$(fg $BR_R $BR_G $BR_B)${A}"
  o="${o}$(fg $BG_R $BG_G $BG_B) $STATUSLINE_WORKTREE "
fi

# ── Render pips ────────────────────────────────────────────────────────────
# Track previous segment color for seamless powerline transitions.
if [ -n "$STATUSLINE_WORKTREE" ]; then
  prev_r=$NOVA_WORKTREE_R; prev_g=$NOVA_WORKTREE_G; prev_b=$NOVA_WORKTREE_B
else
  prev_r=$BR_R; prev_g=$BR_G; prev_b=$BR_B
fi

render_pip() {
  # Usage: render_pip R G B "text"
  o="${o}$(bg "$1" "$2" "$3")$(fg $prev_r $prev_g $prev_b)${A}"
  o="${o}$(fg $BG_R $BG_G $BG_B) ${4} "
  prev_r=$1; prev_g=$2; prev_b=$3
}

has_pips=0

[ "$stash_count" -gt 0 ] && {
  has_pips=1
  render_pip $NOVA_GIT_STASH_R $NOVA_GIT_STASH_G $NOVA_GIT_STASH_B "\$${stash_count}"
}

[ "$conflict_count" -gt 0 ] && {
  has_pips=1
  render_pip $NOVA_GIT_CONFLICT_R $NOVA_GIT_CONFLICT_G $NOVA_GIT_CONFLICT_B "!${conflict_count}"
}

[ "$untracked_count" -gt 0 ] && {
  has_pips=1
  render_pip $NOVA_GIT_UNTRACKED_R $NOVA_GIT_UNTRACKED_G $NOVA_GIT_UNTRACKED_B "?${untracked_count}"
}

[ "$unstaged_count" -gt 0 ] && {
  has_pips=1
  render_pip $NOVA_GIT_UNSTAGED_R $NOVA_GIT_UNSTAGED_G $NOVA_GIT_UNSTAGED_B "~${unstaged_count}"
}

[ "$staged_count" -gt 0 ] && {
  has_pips=1
  render_pip $NOVA_GIT_STAGED_R $NOVA_GIT_STAGED_G $NOVA_GIT_STAGED_B "+${staged_count}"
}

[ "$ahead" -gt 0 ] && {
  has_pips=1
  render_pip $NOVA_GIT_AHEAD_R $NOVA_GIT_AHEAD_G $NOVA_GIT_AHEAD_B "↑${ahead}"
}

[ "$behind" -gt 0 ] && {
  has_pips=1
  render_pip $NOVA_GIT_BEHIND_R $NOVA_GIT_BEHIND_G $NOVA_GIT_BEHIND_B "↓${behind}"
}

# Clean: no active pips
[ "$has_pips" -eq 0 ] && render_pip $NOVA_GIT_CLEAN_R $NOVA_GIT_CLEAN_G $NOVA_GIT_CLEAN_B "✓"

# Closing arrow
o="${o}$(rst)$(fg $prev_r $prev_g $prev_b)${A}$(rst)"
printf '%s' "$o"
