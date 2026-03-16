#!/bin/sh
# prompt-repo-dir.sh — Repo link + directory powerline segment for starship
# Outputs: [/PN2][GH REPO on PN2][PN2→SS1][DIR on SS1]
# Leaves bg at SS1 (#D8DEE9) so git-powerline.sh can transition from there.

. "$HOME/dotFiles/theme.sh"

# Powerline glyphs
A=""
D=""
GH=""

# Colors (RGB triplets for ANSI 24-bit)
TERM_R=46;  TERM_G=52;  TERM_B=64       # #2E3440 Nord0
PN2_R=67;   PN2_G=76;   PN2_B=94        # #434C5E Nord2
SS1_R=216;  SS1_G=222;  SS1_B=233       # #D8DEE9 Nord4
FG_L_R=236; FG_L_G=239; FG_L_B=244     # #ECEFF4 Nord6 (light text)
FG_D_R=46;  FG_D_G=52;  FG_D_B=64      # #2E3440 Nord0 (dark text)

fg() { printf '\033[38;2;%d;%d;%dm' "$1" "$2" "$3"; }
bg() { printf '\033[48;2;%d;%d;%dm' "$1" "$2" "$3"; }

# ANSI helpers for escape sequences printf '%s' can't interpret
_ul_on=$(printf '\033[4m')
_ul_off=$(printf '\033[24m')
_osc8() { printf '\033]8;;%s\a' "$1"; }

# -- Repo info -----------------------------------------------------------------
repo_url=""
repo_name=""
if git rev-parse --git-dir > /dev/null 2>&1; then
  _remote=$(git remote get-url origin 2>/dev/null)
  if [ -n "$_remote" ]; then
    repo_url=$(echo "$_remote" | sed 's|git@github.com:|https://github.com/|' | sed 's|\.git$||')
    repo_name=$(basename "$repo_url")
  fi
fi

# -- Directory (last 2 components, ~/ prefix) ----------------------------------
cwd=$(pwd)
_home="${HOME:-$(eval echo ~)}"
_home="${_home%/}"
case "$cwd" in
  "$_home"*) home_rel="~${cwd#"$_home"}" ;;
  *) home_rel="$cwd" ;;
esac
_depth=$(printf '%s' "$home_rel" | tr -cd '/' | wc -c | tr -d ' ')
if [ "$_depth" -le 1 ]; then
  dir_display="$home_rel"
else
  dir_display=$(printf '%s' "$home_rel" | rev | cut -d/ -f1-2 | rev)
fi

# -- Build output --------------------------------------------------------------
o=""

if [ -n "$repo_name" ]; then
  # Opening: diagonal edge from term bg into PN2
  o="${o}$(bg $TERM_R $TERM_G $TERM_B)$(fg $PN2_R $PN2_G $PN2_B)${D}"
  # GitHub icon + repo name with OSC 8 hyperlink + underline
  o="${o}$(bg $PN2_R $PN2_G $PN2_B)$(fg $FG_L_R $FG_L_G $FG_L_B) ${GH} ${_ul_on}$(_osc8 "$repo_url")${repo_name}$(_osc8 "")${_ul_off} "
  # PN2 -> SS1 transition
  o="${o}$(bg $SS1_R $SS1_G $SS1_B)$(fg $PN2_R $PN2_G $PN2_B)${A}"
else
  # No repo: diagonal edge from term bg into SS1
  o="${o}$(bg $TERM_R $TERM_G $TERM_B)$(fg $SS1_R $SS1_G $SS1_B)${D}"
fi

# Dir content (SS1 bg, dark text) - no closing arrow, git-powerline.sh handles transition
o="${o}$(bg $SS1_R $SS1_G $SS1_B)$(fg $FG_D_R $FG_D_G $FG_D_B) ${dir_display} "

printf '%s' "$o"
