#\!/usr/bin/env bash
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
dir_seg=$(printf "\e[49m\e[38;2;59;66;82m\e[48;2;59;66;82m\e[38;2;236;239;244m\e[22m %s " "$dir_display")
# Git segment handles its own Nord1->Nord6 transition + status arrows + exit
git_seg=$(~/dotFiles/starship-scripts/git-powerline.sh 2>/dev/null)

# -- Bottom row: context bar + model -----------------------------------------
if [ -n "$used_pct" ]; then
  used_int=${used_pct%.*}
  filled=$(( used_int * 8 / 100 ))
  [ "$filled" -gt 8 ] && filled=8
  bar=''
  i=0
  while [ "$i" -lt "$filled" ]; do
    bar="${bar}█"
    i=$(( i + 1 ))
  done
  while [ "$i" -lt 8 ]; do
    bar="${bar}░"
    i=$(( i + 1 ))
  done
  val_text="$bar"
else
  val_text='░░░░░░░░'
fi

if [ -n "$model" ]; then
  context_exit="\e[48;2;236;239;244m\e[38;2;59;66;82m"
  model_seg=$(printf \
    "\e[48;2;236;239;244m\e[38;2;46;52;64m\e[22m %s \e[49m\e[38;2;236;239;244m\e[0m" \
    "$model")
else
  context_exit="\e[0m"
  model_seg=''
fi

context_seg=$(printf \
  "\e[48;2;59;66;82m\e[38;2;236;239;244m\e[22m CONTEXT  %s  ${context_exit}" \
  "$val_text")

# Top row (starship-style) then bottom row (context/model)
printf "%b%s\n%b%b" "$dir_seg" "$git_seg" "$context_seg" "$model_seg"
