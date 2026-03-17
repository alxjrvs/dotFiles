#!/usr/bin/env bash
# Claude Code status line - two rows:
#   Line 1: [repo link OR dir][git branch][worktree?][git pips]
#   Line 2: [cost][time][context bar][model]

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // empty' | sed 's/ [0-9][0-9.]*//g')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

cost_usd=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')

worktree_name=$(echo "$input" | jq -r '.worktree.name // empty')
project_dir=$(echo "$input" | jq -r '.workspace.project_dir // empty')

# -- Formatting ----------------------------------------------------------------
cost_fmt=$(printf '$%.2f' "$cost_usd")

duration_sec=$(( ${duration_ms%%.*} / 1000 ))
dur_hr=$(( duration_sec / 3600 ))
dur_min=$(( (duration_sec % 3600) / 60 ))
dur_sec=$(( duration_sec % 60 ))
if [ "$dur_hr" -gt 0 ]; then
  dur_fmt="${dur_hr}h ${dur_min}m"
elif [ "$dur_min" -gt 0 ]; then
  dur_fmt="${dur_min}m ${dur_sec}s"
else
  dur_fmt="${dur_sec}s"
fi

# -- Directory -----------------------------------------------------------------
cwd=$(echo "$input" | jq -r '.workspace.current_dir // empty')
[ -n "$worktree_name" ] && [ -n "$project_dir" ] && cwd="$project_dir"
[ -z "$cwd" ] && cwd=$(pwd)
_home="${HOME:-$(eval echo ~)}"
_home="${_home%/}"
[ -z "$_home" ] && _home="/Users/$(id -un)"
case "$cwd" in
  "$_home"*) home_rel="~${cwd#"$_home"}" ;;
  *) home_rel="$cwd" ;;
esac
IFS='/' read -ra _parts <<< "$home_rel"
_n=${#_parts[@]}
if [ "$_n" -le 2 ]; then
  dir_display="$home_rel"
else
  dir_display="${_parts[$(( _n - 2 ))]}/${_parts[$(( _n - 1 ))]}"
fi

# -- Repo link ----------------------------------------------------------------
repo_url=""
repo_name=""
if git rev-parse --git-dir > /dev/null 2>&1; then
  _remote=$(git remote get-url origin 2>/dev/null)
  if [ -n "$_remote" ]; then
    repo_url=$(echo "$_remote" | sed 's|git@github.com:|https://github.com/|' | sed 's|\.git$||')
    repo_name=$(basename "$repo_url")
  fi
fi

export STATUSLINE_WORKTREE="$worktree_name"

# -- PR check status (cached 60s) ---------------------------------------------
PR_BG="67;76;94"
PR_FG="236;239;244"
if [ -n "$repo_name" ] && command -v gh >/dev/null 2>&1; then
  _branch=$(git branch --show-current 2>/dev/null)
  if [ -n "$_branch" ]; then
    _cache_dir="/tmp/git-pr-status"
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
      printf "%s\n%s\n%s" "$_now" "$pr_status" "$pr_url" > "$_cache_file"
    fi

    case "$pr_status" in
      pass)    PR_BG="163;190;140"; PR_FG="46;52;64" ;;
      pending) PR_BG="235;203;139"; PR_FG="46;52;64" ;;
      fail)    PR_BG="191;97;106";  PR_FG="236;239;244" ;;
    esac
  fi
fi

git_seg=$(~/dotFiles/starship-scripts/git-powerline.sh --no-prompt 2>/dev/null)

# -- Colors --------------------------------------------------------------------
A=''  # solid arrow
T=''  # thin separator

# Alternating Polar Night / Snow Storm, offset between rows
# Line 1: REPO/DIR=PN2 (dark), BRANCH=SS1 (light, handled by git-powerline.sh)
# Line 2: MODEL=SS1, COST=PN2, TIME=SS2, CONTEXT=PN1
DARK_FG="46;52;64"         # #2E3440 Nord0
TXT="236;239;244"          # #ECEFF4 Nord6 (light text on dark bg)
TXT_DARK="46;52;64"        # #2E3440 Nord0 (dark text on light bg)

REPO_BG="67;76;94"            # #434C5E Nord2 (Polar Night 2)
REPO_FG="${TXT}"

DIR_BG="67;76;94"          # #434C5E Nord2 (Polar Night 2, matches REPO)
DIR_FG="${TXT}"

MODEL_BG="216;222;233"     # #D8DEE9 Nord4 (Snow Storm 1)
MODEL_FG="${TXT_DARK}"

COST_BG="67;76;94"         # #434C5E Nord2 (Polar Night 2)
COST_FG="${TXT}"

TIME_BG="229;233;240"      # #E5E9F0 Nord5 (Snow Storm 2)
TIME_FG="${TXT_DARK}"

LIGHT_BG="59;66;82"        # #3B4252 Nord1 (Polar Night 1, CONTEXT label)

# == Line 1: Repo OR Dir + Git =================================================
line1=""

if [ -n "$repo_name" ]; then
  if [ "${pr_status:-none}" != "none" ]; then
    # PR exists: GH icon on PR-status bg, arrow into repo name on REPO_BG
    line1="${line1}\e[48;2;${DARK_FG}m\e[38;2;${PR_BG}m\e[48;2;${PR_BG}m\e[38;2;${PR_FG}m\e[22m \e]8;;${pr_url}\a\e]8;;\a \e[48;2;${REPO_BG}m\e[38;2;${PR_BG}m\e[38;2;${REPO_FG}m\e[22m \e[4m\e]8;;${repo_url}\a${repo_name}\e]8;;\a\e[24m "
  else
    # No PR: single segment, GH icon + repo name on REPO_BG (original style)
    line1="${line1}\e[48;2;${DARK_FG}m\e[38;2;${PR_BG}m\e[48;2;${PR_BG}m\e[38;2;${PR_FG}m\e[22m  \e[48;2;${REPO_BG}m\e[38;2;${PR_BG}m\e[38;2;${REPO_FG}m  \e[4m\e]8;;${repo_url}\a${repo_name}\e]8;;\a\e[24m "
  fi
else
  # Dir segment (dark bg, light text)
  line1="${line1}\e[48;2;${DARK_FG}m\e[38;2;${DIR_BG}m\e[48;2;${DIR_BG}m\e[38;2;${DIR_FG}m\e[22m ${dir_display} "
fi

# Git or segment closing arrow
if [ -n "$git_seg" ]; then
  printf "%b%s\n" "$line1" "$git_seg"
else
  printf "%b\e[0m\e[38;2;${DIR_BG}m${A}\e[0m\n" "$line1"
fi

# == Line 2: Cost + Time + Context + Model =====================================

# -- Context bar (20 pips, 5% each) --------------------------------------------
# Gradient: Nord2 blue-grey -> amber (~45%) -> red (~85%) -> white hot (100%)
GRAD_0="67;76;94"
GRAD_1="88;92;100"
GRAD_2="108;107;105"
GRAD_3="129;123;111"
GRAD_4="149;138;116"
GRAD_5="170;154;122"
GRAD_6="190;170;127"
GRAD_7="211;185;133"
GRAD_8="232;201;138"
GRAD_9="230;192;136"
GRAD_10="225;178;131"
GRAD_11="219;165;127"
GRAD_12="214;152;123"
GRAD_13="208;139;119"
GRAD_14="203;126;115"
GRAD_15="198;114;111"
GRAD_16="192;101;107"
GRAD_17="203;134;142"
GRAD_18="219;187;193"
GRAD_19="236;239;244"
grad=("$GRAD_0" "$GRAD_1" "$GRAD_2" "$GRAD_3" "$GRAD_4" "$GRAD_5" "$GRAD_6" "$GRAD_7" "$GRAD_8" "$GRAD_9" "$GRAD_10" "$GRAD_11" "$GRAD_12" "$GRAD_13" "$GRAD_14" "$GRAD_15" "$GRAD_16" "$GRAD_17" "$GRAD_18" "$GRAD_19")

if [ -n "$used_pct" ]; then
  used_int=${used_pct%%.*}
  filled=$(( used_int * 20 / 100 ))
  [ "$filled" -gt 20 ] && filled=20
  # At least 1 pip when there's any usage
  [ "$used_int" -gt 0 ] && [ "$filled" -eq 0 ] && filled=1
else
  filled=0
fi

bar=''
i=0
while [ "$i" -lt "$filled" ]; do
  if [ "$i" -eq $(( filled - 1 )) ]; then
    # Last filled pip: bg = terminal bg
    bar="${bar}\e[38;2;${grad[$i]}m\e[48;2;${DARK_FG}m"
    # Percentage floats right of last colored pip (light text on terminal bg)
    bar="${bar}\e[38;2;${TXT}m${used_int}%"
  else
    # Filled pip: fg = this color, bg = next color
    bar="${bar}\e[38;2;${grad[$i]}m\e[48;2;${grad[$(( i + 1 ))]}m"
  fi
  i=$(( i + 1 ))
done
# Unfilled pips: invisible
while [ "$i" -lt 20 ]; do
  bar="${bar}\e[38;2;${DARK_FG}m\e[48;2;${DARK_FG}m"
  i=$(( i + 1 ))
done
val_text="$bar"

# Arrow: CONTEXT label -> bar area
if [ "$filled" -gt 0 ]; then
  left_glyph="\e[48;2;${grad[0]}m\e[38;2;${LIGHT_BG}m"
else
  left_glyph="\e[48;2;${DARK_FG}m\e[38;2;${LIGHT_BG}m"
fi

# Arrow: bar area -> terminal (closing)
bar_exit="\e[0m\e[38;2;${DARK_FG}m\e[0m"

# -- Build line 2 --------------------------------------------------------------
line2=""

# Model segment (opening pill, if present)
if [ -n "$model" ]; then
  line2="${line2}\e[48;2;${DARK_FG}m\e[38;2;${MODEL_BG}m\e[48;2;${MODEL_BG}m\e[38;2;${MODEL_FG}m\e[22m ${model} "
  # Model -> Cost transition
  line2="${line2}\e[48;2;${COST_BG}m\e[38;2;${MODEL_BG}m${A}"
fi

# No model — glyph opens COST segment directly
if [ -z "$model" ]; then
  line2="${line2}\e[48;2;${DARK_FG}m\e[38;2;${COST_BG}m"
fi

# Cost segment
line2="${line2}\e[48;2;${COST_BG}m\e[38;2;${COST_FG}m\e[22m ${cost_fmt} "

# Cost -> Time transition
line2="${line2}\e[48;2;${TIME_BG}m\e[38;2;${COST_BG}m${A}"

# Time segment
line2="${line2}\e[48;2;${TIME_BG}m\e[38;2;${TIME_FG}m\e[22m ${dur_fmt} "

# Time -> CONTEXT label transition
line2="${line2}\e[48;2;${LIGHT_BG}m\e[38;2;${TIME_BG}m${A}"

# Context label
line2="${line2}\e[48;2;${LIGHT_BG}m\e[38;2;${TXT}m\e[22m CONTEXT "

# Bar area + closing arrow
line2="${line2}${left_glyph}${val_text}${bar_exit}"

printf "%b" "$line2"
