#!/usr/bin/env bash
# Claude Code status line — single row:
#   [context bar][model][dir][git]

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // empty')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# -- Directory ---------------------------------------------------------------
cwd=$(pwd)
home_rel="${cwd/#$HOME/~}"
IFS='/' read -ra _parts <<< "$home_rel"
_n=${#_parts[@]}
if [ "$_n" -le 2 ]; then
  dir_display="$home_rel"
else
  dir_display="${_parts[$(( _n - 2 ))]}/${_parts[$(( _n - 1 ))]}"
fi

git_seg=$(~/dotFiles/starship-scripts/git-powerline.sh --no-prompt 2>/dev/null)

# -- Colors ------------------------------------------------------------------
A=''  # solid arrow
T=''  # thin separator

LIGHT_BG="236;239;244"     # #ECEFF4 Nord6
DARK_FG="46;52;64"         # #2E3440 Nord0
BAR_BG="128;138;156"       # #808A9C
BAR_FG="236;239;244"       # #ECEFF4
MODEL_BG="229;233;240"     # #E5E9F0 Nord5
DIR_BG="76;86;106"         # #4C566A Nord3
DIR_FG="236;239;244"       # #ECEFF4 Nord6

# -- Context bar --------------------------------------------------------------
if [ -n "$used_pct" ]; then
  used_int=${used_pct%.*}
  filled=$(( used_int * 8 / 100 ))
  [ "$filled" -gt 8 ] && filled=8
  bar=''
  i=0
  while [ "$i" -lt "$filled" ]; do
    if [ "$i" -eq $(( filled - 1 )) ]; then
      bar="${bar}\e[48;2;${DARK_FG}m\e[38;2;${BAR_BG}m${A}"
    else
      bar="${bar}\e[48;2;${BAR_BG}m\e[38;2;${DARK_FG}m${T}"
    fi
    i=$(( i + 1 ))
  done
  while [ "$i" -lt 8 ]; do
    bar="${bar}\e[48;2;${DARK_FG}m\e[38;2;${BAR_FG}m${T}"
    i=$(( i + 1 ))
  done
  val_text="$bar"
else
  filled=0
  val_text=''
  i=0
  while [ "$i" -lt 8 ]; do
    val_text="${val_text}\e[48;2;${DARK_FG}m\e[38;2;${BAR_FG}m${T}"
    i=$(( i + 1 ))
  done
fi

# Arrow: CONTEXT label -> bar area
if [ "$filled" -gt 0 ]; then
  left_glyph="\e[48;2;${BAR_BG}m\e[38;2;${LIGHT_BG}m${A}"
else
  left_glyph="\e[48;2;${DARK_FG}m\e[38;2;${LIGHT_BG}m${A}"
fi

# Arrow: bar area -> next segment (MODEL if present, else DIR)
if [ -n "$model" ]; then
  next_bg="${MODEL_BG}"
else
  next_bg="${DIR_BG}"
fi

if [ "$filled" -ge 8 ]; then
  bar_exit="\e[48;2;${next_bg}m\e[38;2;${BAR_BG}m${A}"
else
  bar_exit="\e[48;2;${next_bg}m\e[38;2;${DARK_FG}m${A}"
fi

# -- Build single row --------------------------------------------------------
o=""

# Context label
o="${o}\e[48;2;${LIGHT_BG}m\e[38;2;${DARK_FG}m\e[22m CONTEXT "

# Bar area + exit arrow
o="${o}${left_glyph}${val_text}${bar_exit}"

# Model segment (if present)
if [ -n "$model" ]; then
  o="${o}\e[48;2;${MODEL_BG}m\e[38;2;${DARK_FG}m\e[22m ${model} "
  # Model -> DIR transition
  o="${o}\e[48;2;${DIR_BG}m\e[38;2;${MODEL_BG}m${A}"
fi

# Dir segment
o="${o}\e[48;2;${DIR_BG}m\e[38;2;${DIR_FG}m\e[22m ${dir_display} "

# Git or dir closing arrow
if [ -n "$git_seg" ]; then
  printf "%b%s" "$o" "$git_seg"
else
  printf "%b\e[0m\e[38;2;${DIR_BG}m${A}\e[0m" "$o"
fi
