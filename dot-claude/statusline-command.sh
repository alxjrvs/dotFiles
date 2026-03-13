#!/usr/bin/env bash
# Claude Code status line — two-tone USAGE + MODEL segments with powerline glyphs

SL=''
BS=''

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // empty')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# -- USAGE segment --------------------------------------------------------
# LABEL bg: #3B4252 (59,66,82)  VALUE bg: #4C566A (76,86,106)
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

# VALUE exit: bg flipped — bg=next LABEL (or term bg), fg=USAGE VALUE
if [ -n "$model" ]; then
  usage_exit_esc='\e[48;2;76;86;106m\e[38;2;46;52;64m'
else
  usage_exit_esc='\e[48;2;46;52;64m\e[38;2;76;86;106m'
fi

# Compose USAGE segment:
#   entry SL (fg=terminal bg on LABEL bg) + LABEL text + transition SL (fg=VALUE bg) + VALUE text + exit BS
usage_seg=$(printf \
  "\e[48;2;59;66;82m\e[38;2;236;239;244m\e[22m USAGE \e[48;2;76;86;106m\e[38;2;59;66;82m%s\e[48;2;76;86;106m\e[38;2;236;239;244m\e[1m %s ${usage_exit_esc}%s\e[0m" \
  "$SL" "$val_text" "$BS")

# -- MODEL segment ---------------------------------------------------------
# LABEL bg: #5E81AC (94,129,172)  VALUE bg: #81A1C1 (129,161,193)
# Entry SL uses fg=terminal bg (#2E3440 = 46,52,64) on MODEL LABEL bg (gap entry pill)
if [ -n "$model" ]; then
  model_seg=$(printf \
    "\e[48;2;94;129;172m\e[38;2;46;52;64m%s\e[48;2;94;129;172m\e[38;2;236;239;244m\e[22m MODEL \e[48;2;129;161;193m\e[38;2;94;129;172m%s\e[48;2;129;161;193m\e[38;2;46;52;64m\e[22m %s \e[38;2;46;52;64m%s\e[0m" \
    "$SL" "$SL" "$model" "$BS")
else
  model_seg=''
fi

printf "%b%b" "$usage_seg" "$model_seg"
