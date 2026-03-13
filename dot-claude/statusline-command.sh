#!/usr/bin/env bash
# Claude Code status line — two rows:
#   top:    starship-style directory + git
#   bottom: context bar + model

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // empty')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# -- Top row: directory + git ------------------------------------------------
cwd=$(pwd)
home_rel="${cwd/#$HOME/~}"
IFS='/' read -ra _parts <<< "$home_rel"
_n=${#_parts[@]}
if [ "$_n" -le 2 ]; then
  dir_display="$home_rel"
else
  dir_display="${_parts[$(( _n - 2 ))]}/${_parts[$(( _n - 1 ))]}"
fi

# Entry E0B0: terminal -> Nord1; dir segment: Nord1 bg, Nord6 fg
dir_seg=$(printf "\e[48;2;59;66;82m\e[38;2;236;239;244m\e[22m %s " "$dir_display")
# Git segment handles its own Nord1->Nord6 transition + status arrows + exit
git_seg=$(~/dotFiles/starship-scripts/git-powerline.sh --no-prompt 2>/dev/null)

# -- Bottom row: context bar + model -----------------------------------------
# Powerline glyphs
A=''  # solid arrow
T=''  # thin separator

# Colors
LIGHT_BG="236;239;244"     # #ECEFF4
DARK_FG="46;52;64"         # #2E3440
BAR_BG="128;138;156"       # #808A9C
BAR_FG="236;239;244"       # #ECEFF4
MODEL_BG="229;233;240"     # #E5E9F0

if [ -n "$used_pct" ]; then
  used_int=${used_pct%.*}
  filled=$(( used_int * 8 / 100 ))
  [ "$filled" -gt 8 ] && filled=8
  bar=''
  i=0
  while [ "$i" -lt "$filled" ]; do
    if [ "$i" -eq $(( filled - 1 )) ]; then
      bar="${bar}\e[48;2;${BAR_BG}m\e[38;2;${BAR_FG}m${A}"
    else
      bar="${bar}\e[48;2;${BAR_FG}m\e[38;2;${BAR_BG}m${T}"
    fi
    i=$(( i + 1 ))
  done
  while [ "$i" -lt 8 ]; do
    bar="${bar}\e[48;2;${BAR_BG}m\e[38;2;${BAR_FG}m${T}"
    i=$(( i + 1 ))
  done
  val_text="$bar"
else
  filled=0
  val_text='        '
fi

# Left glyph: E0B1 (thin) when pips active, E0B0 (solid) when empty
if [ "$filled" -gt 0 ]; then
  left_glyph="\e[48;2;${LIGHT_BG}m\e[38;2;${DARK_FG}m${T}\e[48;2;${BAR_BG}m\e[38;2;${BAR_FG}m"
else
  left_glyph="\e[48;2;${BAR_BG}m\e[38;2;${LIGHT_BG}m${A}"
fi

# Right glyph: E0B1 at 100%, E0B0 otherwise
if [ -n "$model" ]; then
  if [ "$filled" -ge 8 ]; then
    context_exit="\e[48;2;${LIGHT_BG}m\e[38;2;${DARK_FG}m${T}"
  else
    context_exit="\e[48;2;${MODEL_BG}m\e[38;2;${BAR_BG}m${A}"
  fi
  model_seg=$(printf     "\e[48;2;${MODEL_BG}m\e[38;2;${DARK_FG}m\e[22m %s \e[49m\e[38;2;${MODEL_BG}m${A}\e[0m"     "$model")
else
  context_exit="\e[0m"
  model_seg=''
fi

context_seg=$(printf   "\e[48;2;${LIGHT_BG}m\e[38;2;${DARK_FG}m\e[22m CONTEXT ${left_glyph}%s${context_exit}"   "$val_text")

# Top row (starship-style) then bottom row (context/model)
printf "%b%s

%b%b" "$dir_seg" "$git_seg" "$context_seg" "$model_seg"
