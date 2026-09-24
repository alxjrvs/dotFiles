#!/bin/bash
# On power, the Mac never idles to sleep, so an unattended /loop is not cut off mid-flight. A
# closed lid still sleeps. Every apply: present costs one pmset read. The change needs sudo,
# so a run with no terminal to ask on reports it instead of failing the scripts after it.
set -euo pipefail
sleep=$(pmset -g custom | awk '/^AC Power/ { ac = 1 } ac && $1 == "sleep" { print $2; exit }')
[ "$sleep" = 0 ] && exit 0
if [ -t 0 ]; then
  sudo pmset -c sleep 0 || echo "sleep: could not set; run 'sudo pmset -c sleep 0'" >&2
else
  echo "sleep: run 'sudo pmset -c sleep 0' once, or apply from a terminal" >&2
fi
