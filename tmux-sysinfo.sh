#!/bin/sh
# tmux-sysinfo.sh - system info for status-format[0]

UPTIME=$(uptime | sed 's/^.*up //;s/, [0-9]* user.*//')

BAT=$(pmset -g batt 2>/dev/null | grep -o '[0-9]*%' | head -1)
[ -z "$BAT" ] && BAT="--"

CPU=$(ps -A -o %cpu 2>/dev/null | awk 'NR>1{s+=$1} END{printf "%.0f%%", s}')

MEM=$(vm_stat 2>/dev/null | awk '
  /Pages active/  { a=$3+0 }
  /Pages wired/   { w=$3+0 }
  END { printf "%.1fG", (a+w)*4096/1073741824 }
')

printf 'up %s  bat %s  cpu %s  mem %s' "$UPTIME" "$BAT" "$CPU" "$MEM"
