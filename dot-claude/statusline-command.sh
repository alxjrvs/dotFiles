#!/usr/bin/env bash
# Claude Code status line — two-tone USAGE + MODEL segments with powerline glyphs

SL=''
BS=''

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // empty')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# -- USAGE segment --------------------------------------------------------
# LABEL bg: #3e2210 (62,34,16)  VALUE bg: #6e4020 (110,64,32)
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
  usage_exit_esc='\e[48;2;110;64;32m\e[38;2;40;44;52m'
else
  usage_exit_esc='\e[48;2;40;44;52m\e[38;2;110;64;32m'
fi

# Compose USAGE segment:
#   entry SL (fg=terminal bg on LABEL bg) + LABEL text + transition SL (fg=VALUE bg) + VALUE text + exit BS
usage_seg=$(printf \
  "\e[48;2;62;34;16m\e[38;2;240;240;240m\e[22m USAGE \e[48;2;110;64;32m\e[38;2;62;34;16m%s\e[48;2;110;64;32m\e[38;2;240;240;240m\e[1m %s ${usage_exit_esc}%s\e[0m" \
  "$SL" "$val_text" "$BS")

# -- MODEL segment ---------------------------------------------------------
# LABEL bg: #865228 (134,82,40)  VALUE bg: #9e6430 (158,100,48)
# Entry SL uses fg=USAGE VALUE bg (#6e4020 = 110,64,32) on MODEL LABEL bg
if [ -n "$model" ]; then
  model_seg=$(printf \
    "\e[48;2;134;82;40m\e[38;2;40;44;52m%s\e[48;2;134;82;40m\e[38;2;240;240;240m\e[22m MODEL \e[48;2;158;100;48m\e[38;2;134;82;40m%s\e[48;2;158;100;48m\e[38;2;240;240;240m\e[22m %s \e[38;2;40;44;52m%s\e[0m" \
    "$SL" "$SL" "$model" "$BS")
else
  model_seg=''
fi

printf "%b%b" "$usage_seg" "$model_seg"
