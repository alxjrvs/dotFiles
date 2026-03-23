#!/bin/sh
# prompt-repo-dir.sh — Repo link OR directory powerline segment for starship
# With remote: [/PN2][GH REPO on PN2]   Without: [/PN2][DIR on PN2]
# Leaves bg at PN2 (#434C5E) so git-powerline.sh can transition from there.

. "$HOME/dotFiles/theme.sh"

# Source git data cache
bash "$HOME/dotFiles/starship-scripts/git-data.sh"
# shellcheck disable=SC1090
. "/tmp/git-data-cache-$(id -u).sh"

# Powerline glyphs
A=""
D=""
GH=""

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

# -- Repo info (from cache) ----------------------------------------------------
repo_url="$GIT_REPO_HTTPS"
repo_name="$GIT_REPO_NAME"

# -- PR status (from cache) ----------------------------------------------------
pr_bg_r=$SS1_R; pr_bg_g=$SS1_G; pr_bg_b=$SS1_B  # default: model bg (no PR)
pr_fg_r=$FG_D_R; pr_fg_g=$FG_D_G; pr_fg_b=$FG_D_B  # default: dark logo on white bg
pr_status="$GIT_PR_STATUS"
pr_url="$GIT_PR_URL"

case "$pr_status" in
  pass)    pr_bg_r=$NOVA_PR_PASS_R;    pr_bg_g=$NOVA_PR_PASS_G;    pr_bg_b=$NOVA_PR_PASS_B;    pr_fg_r=$FG_D_R; pr_fg_g=$FG_D_G; pr_fg_b=$FG_D_B ;;
  pending) pr_bg_r=$NOVA_PR_PENDING_R; pr_bg_g=$NOVA_PR_PENDING_G; pr_bg_b=$NOVA_PR_PENDING_B; pr_fg_r=$FG_D_R; pr_fg_g=$FG_D_G; pr_fg_b=$FG_D_B ;;
  fail)    pr_bg_r=$NOVA_PR_FAIL_R;    pr_bg_g=$NOVA_PR_FAIL_G;    pr_bg_b=$NOVA_PR_FAIL_B;    pr_fg_r=$FG_L_R; pr_fg_g=$FG_L_G; pr_fg_b=$FG_L_B ;;
esac

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
  # GH icon segment (bg colored by PR status, defaults to PN2 when no PR)
  o="${o}$(bg $TERM_R $TERM_G $TERM_B)$(fg $pr_bg_r $pr_bg_g $pr_bg_b)${D}"
  if [ -n "$pr_url" ]; then
    o="${o}$(bg $pr_bg_r $pr_bg_g $pr_bg_b)$(fg $pr_fg_r $pr_fg_g $pr_fg_b) $(_osc8 "$pr_url")${GH}$(_osc8 "") "
  else
    o="${o}$(bg $pr_bg_r $pr_bg_g $pr_bg_b)$(fg $pr_fg_r $pr_fg_g $pr_fg_b) ${GH} "
  fi
  # Transition: GH icon bg -> PN2 for repo name
  o="${o}$(bg $PN2_R $PN2_G $PN2_B)$(fg $pr_bg_r $pr_bg_g $pr_bg_b)${A}"
  o="${o}$(fg $FG_L_R $FG_L_G $FG_L_B) ${_ul_on}$(_osc8 "$repo_url")${repo_name}$(_osc8 "")${_ul_off} "
else
  # Dir only: diagonal edge from term bg into PN2
  o="${o}$(bg $TERM_R $TERM_G $TERM_B)$(fg $PN2_R $PN2_G $PN2_B)${D}"
  o="${o}$(bg $PN2_R $PN2_G $PN2_B)$(fg $FG_L_R $FG_L_G $FG_L_B) ${dir_display} "
fi

printf '%s' "$o"
