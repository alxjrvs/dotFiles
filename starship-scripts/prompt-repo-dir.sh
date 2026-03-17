#!/bin/sh
# prompt-repo-dir.sh — Repo link OR directory powerline segment for starship
# With remote: [/PN2][GH REPO on PN2]   Without: [/PN2][DIR on PN2]
# Leaves bg at PN2 (#434C5E) so git-powerline.sh can transition from there.

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


# -- PR check status (cached 60s) ---------------------------------------------
pr_bg_r=$FG_L_R; pr_bg_g=$FG_L_G; pr_bg_b=$FG_L_B  # default: white bg (no PR)
pr_fg_r=$FG_D_R; pr_fg_g=$FG_D_G; pr_fg_b=$FG_D_B  # default: dark logo on white bg
if [ -n "$repo_name" ] && command -v gh >/dev/null 2>&1; then
  _cache_dir="/tmp/git-pr-status"
  _branch=$(git branch --show-current 2>/dev/null)
  if [ -n "$_branch" ]; then
    _repo_id=$(git rev-parse --show-toplevel 2>/dev/null | tr '/' '_')
    _cache_file="${_cache_dir}/${_repo_id}_${_branch}"
    _now=$(date +%s)
    _ttl=60
    pr_status="none"
    pr_url=""

    if [ -f "$_cache_file" ]; then
      _cached_time=$(head -1 "$_cache_file")
      _age=$(( _now - ${_cached_time:-0} ))
      if [ "$_age" -lt "$_ttl" ]; then
        pr_status=$(sed -n '2p' "$_cache_file")
        pr_url=$(sed -n '3p' "$_cache_file")
      fi
    fi

    if [ "$pr_status" = "none" ]; then
      mkdir -p "$_cache_dir"
      pr_status=$(gh pr checks --json state --jq '
        if length == 0 then "none"
        elif all(.state == "SUCCESS") then "pass"
        elif any(.state == "FAILURE" or .state == "CANCELLED") then "fail"
        else "pending"
        end
      ' 2>/dev/null || echo "none")
      [ "$pr_status" != "none" ] && pr_url=$(gh pr view --json url --jq .url 2>/dev/null || echo "")
      printf '%s\n%s\n%s' "$_now" "$pr_status" "$pr_url" > "$_cache_file"
    fi

    case "$pr_status" in
      pass)    pr_bg_r=$NOVA_PR_PASS_R;    pr_bg_g=$NOVA_PR_PASS_G;    pr_bg_b=$NOVA_PR_PASS_B;    pr_fg_r=$FG_D_R; pr_fg_g=$FG_D_G; pr_fg_b=$FG_D_B ;;
      pending) pr_bg_r=$NOVA_PR_PENDING_R; pr_bg_g=$NOVA_PR_PENDING_G; pr_bg_b=$NOVA_PR_PENDING_B; pr_fg_r=$FG_D_R; pr_fg_g=$FG_D_G; pr_fg_b=$FG_D_B ;;
      fail)    pr_bg_r=$NOVA_PR_FAIL_R;    pr_bg_g=$NOVA_PR_FAIL_G;    pr_bg_b=$NOVA_PR_FAIL_B;    pr_fg_r=$FG_L_R; pr_fg_g=$FG_L_G; pr_fg_b=$FG_L_B ;;
    esac
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
  # GH icon segment (bg colored by PR status, defaults to PN2 when no PR)
  o="${o}$(bg $TERM_R $TERM_G $TERM_B)$(fg $pr_bg_r $pr_bg_g $pr_bg_b)${D}"
  if [ -n "$pr_url" ]; then
    o="${o}$(bg $pr_bg_r $pr_bg_g $pr_bg_b)$(fg $pr_fg_r $pr_fg_g $pr_fg_b) $(_osc8 "$pr_url")${GH}$(_osc8 "") "
  else
    o="${o}$(bg $pr_bg_r $pr_bg_g $pr_bg_b)$(fg $pr_fg_r $pr_fg_g $pr_fg_b) ${GH} "
  fi
  # Transition: GH icon bg -> PN2 for repo name
  o="${o}$(bg $PN2_R $PN2_G $PN2_B)$(fg $pr_bg_r $pr_bg_g $pr_bg_b)${A}"
  if [ -n "$pr_url" ]; then
    o="${o}$(fg $FG_L_R $FG_L_G $FG_L_B)${_ul_on}$(_osc8 "$repo_url")${repo_name}$(_osc8 "")${_ul_off} "
  else
    o="${o}$(fg $FG_L_R $FG_L_G $FG_L_B) ${_ul_on}$(_osc8 "$repo_url")${repo_name}$(_osc8 "")${_ul_off} "
  fi
else
  # Dir only: diagonal edge from term bg into PN2
  o="${o}$(bg $TERM_R $TERM_G $TERM_B)$(fg $PN2_R $PN2_G $PN2_B)${D}"
  o="${o}$(bg $PN2_R $PN2_G $PN2_B)$(fg $FG_L_R $FG_L_G $FG_L_B) ${dir_display} "
fi

printf '%s' "$o"
