#!/usr/bin/env bash
# Claude Code status line â two rows:
#   Line 1: [dir][git]
#   Line 2: [cost][time][context bar][model]

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // empty' | sed 's/ [0-9][0-9.]*//g')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

cost_usd=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')

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

git_seg=$(~/dotFiles/starship-scripts/git-powerline.sh --no-prompt 2>/dev/null)

# -- Colors --------------------------------------------------------------------
A=''  # solid arrow
T=''  # thin separator

# Gradient stops (dark left -> slightly lighter right, all Polar Night)
# Line 1: DIR=Nord1, BRANCH=Nord3 (handled by git-powerline.sh)
# Line 2: MODEL=Nord0, COST=Nord1, TIME=Nord2, CONTEXT=Nord3
DARK_FG="46;52;64"         # #2E3440 Nord0
TXT="236;239;244"          # #ECEFF4 Nord6 (all text)

DIR_BG="59;66;82"          # #3B4252 Nord1
DIR_FG="${TXT}"

MODEL_BG="46;52;64"        # #2E3440 Nord0
MODEL_FG="${TXT}"

COST_BG="59;66;82"         # #3B4252 Nord1
COST_FG="${TXT}"

TIME_BG="67;76;94"         # #434C5E Nord2
TIME_FG="${TXT}"

LIGHT_BG="76;86;106"       # #4C566A Nord3 (CONTEXT label)

# == Line 1: Dir + Git ========================================================
line1=""

# Dir segment (opening pill)
line1="${line1}\e[48;2;${DIR_BG}m\e[38;2;${DIR_FG}m\e[22m ${dir_display} "

# Git or dir closing arrow
if [ -n "$git_seg" ]; then
  printf "%b%s\n" "$line1" "$git_seg"
else
  printf "%b\e[0m\e[38;2;${DIR_BG}m${A}\e[0m\n" "$line1"
fi

# == Line 2: Cost + Time + Context + Model =====================================

# -- Context bar (20 pips, 5% each) --------------------------------------------
# Gradient: Nord3 blue-grey -> amber (~45%) -> red (~85%) -> white hot (100%)
GRAD_0="96;106;126"
GRAD_1="108;113;123"
GRAD_2="120;120;119"
GRAD_3="135;129;118"
GRAD_4="154;143;122"
GRAD_5="174;158;126"
GRAD_6="193;172;130"
GRAD_7="213;187;134"
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
    bar="${bar}\e[38;2;${TXT}m ${used_int}%"
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
  line2="${line2}\e[48;2;${MODEL_BG}m\e[38;2;${MODEL_FG}m\e[22m ${model} "
  # Model -> Cost transition
  line2="${line2}\e[48;2;${COST_BG}m\e[38;2;${MODEL_BG}m${A}"
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
