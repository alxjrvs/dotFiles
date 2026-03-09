#!/bin/sh
# tmux-sysinfo.sh [stat] — outputs a single stat for status bar use
# Stats: uptime | bat | cpu | mem

case "${1:-}" in
  uptime)
    uptime | sed 's/^.*up //;s/, [0-9]* user.*//'
    ;;
  bat)
    v=$(pmset -g batt 2>/dev/null | grep -o '[0-9]*%' | head -1)
    printf '%s' "${v:---}"
    ;;
  cpu)
    ps -A -o %cpu 2>/dev/null | awk 'NR>1{s+=$1} END{printf "%.0f%%", s}'
    ;;
  mem)
    vm_stat 2>/dev/null | awk '
      /Pages active/  { a=$3+0 }
      /Pages wired/   { w=$3+0 }
      END { printf "%.1fG", (a+w)*4096/1073741824 }'
    ;;
esac
