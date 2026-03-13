#!/usr/bin/env bash
# Claude Code status line — two rows:
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
dur_min=$(( duration_sec / 60 ))
dur_sec=$(( duration_sec % 60 ))
if [ "$dur_min" -gt 0 ]; then
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

LIGHT_BG="236;239;244"     # #ECEFF4 Nord6
DARK_FG="46;52;64"         # #2E3440 Nord0
BAR_BG="128;138;156"       # #808A9C
BAR_FG="236;239;244"       # #ECEFF4
MODEL_BG="229;233;240"     # #E5E9F0 Nord5
DIR_BG="76;86;106"         # #4C566A Nord3
DIR_FG="236;239;244"       # #ECEFF4 Nord6
WARN_BG="235;203;139"      # #EBCB8B git yellow
CRIT_BG="191;97;106"       # #BF616A git red
COST_BG="229;233;240"      # #E5E9F0 Nord5 (matches git branch)
COST_FG="46;52;64"         # #2E3440 Nord0
TIME_BG="76;86;106"        # #4C566A Nord3 (matches CWD)
TIME_FG="236;239;244"      # #ECEFF4 Nord6

# == Line 1: Dir + Git ========================================================
line1=""

# Dir segment (opening pill)
line1="${line1}\e[48;2;${DIR_BG}m\e[38;2;${DIR_FG}m\e[22m ${dir_display} "

# Git or dir closing arrow
if [ -n "$git_seg" ]; then
  printf "%b%s
" "$line1" "$git_seg"
else
  printf "%b\e[0m\e[38;2;${DIR_BG}m${A}\e[0m
" "$line1"
fi

# == Line 2: Cost + Time + Context + Model =====================================

# -- Context bar ---------------------------------------------------------------
# Gradient: DIR_BG -> yellow (~50%) -> red (~80%) -> white hot (100%)
GRAD_0="76;86;106"
GRAD_1="129;125;117"
GRAD_2="182;164;128"
GRAD_3="235;203;139"
GRAD_4="220;167;128"
GRAD_5="205;132;117"
GRAD_6="191;97;106"
GRAD_7="236;239;244"
grad=("$GRAD_0" "$GRAD_1" "$GRAD_2" "$GRAD_3" "$GRAD_4" "$GRAD_5" "$GRAD_6" "$GRAD_7")

if [ -n "$used_pct" ]; then
  used_int=${used_pct%%.*}
  filled=$(( used_int * 8 / 100 ))
  [ "$filled" -gt 8 ] && filled=8
else
  filled=0
fi

bar=''
i=0
while [ "$i" -lt "$filled" ]; do
  if [ "$i" -eq $(( filled - 1 )) ]; then
    # Last filled pip: bg = terminal bg
    bar="${bar}\e[38;2;${grad[$i]}m\e[48;2;${DARK_FG}m"
  else
    # Filled pip: fg = this color, bg = next color
    bar="${bar}\e[38;2;${grad[$i]}m\e[48;2;${grad[$(( i + 1 ))]}m"
  fi
  i=$(( i + 1 ))
done
# Unfilled pips: invisible
while [ "$i" -lt 8 ]; do
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
  line2="${line2}\e[48;2;${DIR_BG}m\e[38;2;${DIR_FG}m\e[22m ${model} "
  # Model -> Cost transition
  line2="${line2}\e[48;2;${COST_BG}m\e[38;2;${DIR_BG}m${A}"
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
line2="${line2}\e[48;2;${LIGHT_BG}m\e[38;2;${DARK_FG}m\e[22m CONTEXT "

# Bar area + closing arrow
line2="${line2}${left_glyph}${val_text}${bar_exit}"

printf "%b" "$line2"
