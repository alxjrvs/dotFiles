#!/bin/sh
# tmux-data.sh - Raw system stat values
# Usage: tmux-data.sh <cpu|mem|bat>
# Called by tmux-powerline.sh for dynamic values. No formatting.

case "${1:-}" in
  cpu)
    raw=$(ps -A -o %cpu 2>/dev/null | awk 'NR>1{s+=$1} END{printf "%.0f", s}')
    cores=$(sysctl -n hw.logicalcpu 2>/dev/null || echo 1)
    val=$(awk "BEGIN {v=int(${raw:-0}/${cores}); printf \"%d\", (v>100?100:v)}")
    printf '%s' "${val:-0}"
    ;;
  mem)
    vm_stat 2>/dev/null | awk '
      /Pages active/  { a=$3+0 }
      /Pages wired/   { w=$3+0 }
      END { printf "%.1fG", (a+w)*4096/1073741824 }'
    ;;
  bat)
    batt_info=$(pmset -g batt 2>/dev/null)
    val=$(echo "$batt_info" | grep -o '[0-9]*%' | head -1 | tr -d '%')
    [ -z "$val" ] && val=0
    charging=""
    echo "$batt_info" | grep -q "AC Power" && charging="⚡"
    printf '%s%s' "$charging" "$val"
    ;;
  all)
    # Output all stats in one invocation: cpu|mem|bat
    raw=$(ps -A -o %cpu 2>/dev/null | awk 'NR>1{s+=$1} END{printf "%.0f", s}')
    cores=$(sysctl -n hw.logicalcpu 2>/dev/null || echo 1)
    cpu_val=$(awk "BEGIN {v=int(${raw:-0}/${cores}); printf \"%d\", (v>100?100:v)}")
    mem_val=$(vm_stat 2>/dev/null | awk '
      /Pages active/  { a=$3+0 }
      /Pages wired/   { w=$3+0 }
      END { printf "%.1fG", (a+w)*4096/1073741824 }')
    batt_info=$(pmset -g batt 2>/dev/null)
    bat_val=$(echo "$batt_info" | grep -o '[0-9]*%' | head -1 | tr -d '%')
    [ -z "$bat_val" ] && bat_val=0
    bat_charging=""
    echo "$batt_info" | grep -q "AC Power" && bat_charging="⚡"
    printf '%s|%s|%s%s' "${cpu_val:-0}" "$mem_val" "$bat_charging" "$bat_val"
    ;;
esac
