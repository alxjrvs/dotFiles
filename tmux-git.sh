#!/bin/sh
# tmux-git.sh <pane_current_path>
# Matches starship git_branch + git_status + custom.git_clean exactly

dir="$1"
cd "$dir" 2>/dev/null || { printf '#[bg=default,fg=#8350C2]'; exit 0; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { printf '#[bg=default,fg=#8350C2]'; exit 0; }

branch=$(git branch --show-current 2>/dev/null)
[ -z "$branch" ] && branch=$(git rev-parse --short HEAD 2>/dev/null)
[ -z "$branch" ] && { printf '#[bg=default,fg=#8350C2]'; exit 0; }

# ── Status indicators (starship git_status symbols) ──────────────────────
porcelain=$(git status --porcelain 2>/dev/null)
conflicted=0; staged=0; modified=0; renamed=0; deleted=0; stashed=0; untracked=0
echo "$porcelain" | grep -q '^[UAD][UAD]' 2>/dev/null && conflicted=1
echo "$porcelain" | grep -q '^[^? ]'      2>/dev/null && staged=1
echo "$porcelain" | grep -q '^.[M]'        2>/dev/null && modified=1
echo "$porcelain" | grep -q '^R'           2>/dev/null && renamed=1
echo "$porcelain" | grep -q '^.[D]'        2>/dev/null && deleted=1
git stash list 2>/dev/null | grep -q .                 && stashed=1
echo "$porcelain" | grep -q '^??'          2>/dev/null && untracked=1

all_status=""
[ "$conflicted" = "1" ] && all_status="${all_status}="
[ "$staged"     = "1" ] && all_status="${all_status}+"
[ "$modified"   = "1" ] && all_status="${all_status}!"
[ "$renamed"    = "1" ] && all_status="${all_status}»"
[ "$deleted"    = "1" ] && all_status="${all_status}✘"
[ "$stashed"    = "1" ] && all_status="${all_status}"'$'
[ "$untracked"  = "1" ] && all_status="${all_status}?"

# ── Ahead / behind ────────────────────────────────────────────────────────
ahead_behind=""
if git rev-parse --verify "@{u}" >/dev/null 2>&1; then
  ahead=$(git rev-list --count "@{u}..HEAD" 2>/dev/null || echo 0)
  behind=$(git rev-list --count "HEAD..@{u}" 2>/dev/null || echo 0)
  if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
    ahead_behind="⇕"
  elif [ "$ahead" -gt 0 ]; then
    ahead_behind="⇡${ahead}"
  elif [ "$behind" -gt 0 ]; then
    ahead_behind="⇣${behind}"
  fi
fi

# ── Output: [purple→dark] [dark: branch_icon branch] [optional status] ───
printf '#[bg=default,fg=#8350C2]#[bg=default,fg=#ffffff,bold]  %s ' "$branch"

combined="${all_status}${ahead_behind}"
if [ -n "$combined" ]; then
  # dirty/ahead/behind → yellow (starship git_status: bg=#f5c211)
  printf '#[bg=#f5c211,fg=#4a4a4a]#[bg=#f5c211,fg=#2d1f00,bold] %s #[bg=default,fg=#f5c211]' "$combined"
elif git rev-parse --verify "@{u}" >/dev/null 2>&1; then
  # clean + in sync → green ✓ (starship custom.git_clean)
  printf '#[bg=#2e8b57,fg=#4a4a4a]#[bg=#2e8b57,fg=#ffffff,bold]  ✓ #[bg=default,fg=#2e8b57]'
else
  printf '#[bg=default,fg=#8350C2]'
fi
# clean + no remote: closing arrow in dir color
