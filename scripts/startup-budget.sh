#!/usr/bin/env sh
# Interactive shell startup stays under a ceiling.
#
# WHY THIS AND NOT A COMMENT. zsh/30-plugins.zsh carries a careful baseline —
# per-eval breakdown, what was tried, what was rejected and why — and it is
# maintained honestly: it was re-measured, the number moved 199 → 250 ms, and the
# comment says so and names the command to re-run. That is exactly the shape
# DECISIONS.md's "How to write a number so it cannot rot" asks for.
#
# It still only rots slower. A comment cannot notice; someone has to re-run it,
# and the drift it is tracking is tool growth — six `eval`s of six independently
# upgrading tools, none of which announces that it got heavier. The whole reason
# CLAUDE.md bans measurements against a tool version is that they expire with
# nobody watching, and the repo's own answer to that is to enforce rather than
# describe. This is the enforcement half; the comment stays as the explanation.
#
# A CEILING, NOT A BASELINE. It fails on "materially worse than measured", not on
# "different from measured" — a machine under load, a cold cache, or a Rosetta
# shell all move the number, and a check that fires on those trains you to ignore
# it. Set well above the ~250 ms baseline so it means "something changed
# structurally", which is the only signal worth a notification.
#
# Verify-only, and machine state: CI has no sheldon, no atuin, no mise shims and
# no plugins, so a runner would measure a shell that does not exist here.
#
# Usage: scripts/startup-budget.sh [ceiling-ms]
set -eu

CEILING=${1:-${STARTUP_CEILING_MS:-450}}
RUNS=${STARTUP_RUNS:-5}
SHELL_BIN=${STARTUP_SHELL:-zsh}

command -v "$SHELL_BIN" > /dev/null 2>&1 || {
  echo "startup-budget: no $SHELL_BIN on PATH — nothing was measured" >&2
  exit 1
}

# Median of N, not mean: one scheduler hiccup should not decide this, and the
# first run is reliably cold (the cache the later ones benefit from).
i=0
times=''
while [ "$i" -lt "$RUNS" ]; do
  i=$((i + 1))
  start=$(date +%s%N 2> /dev/null || printf '')
  if [ -z "$start" ] || [ "$start" = "$(date +%s)N" ]; then
    # BSD date has no %N. Fall back to python, which is present on macOS.
    ms=$(python3 -c "
import subprocess, time
t = time.time()
subprocess.run(['$SHELL_BIN', '-i', '-c', 'exit'], capture_output=True)
print(int((time.time() - t) * 1000))
" 2> /dev/null || printf '')
  else
    "$SHELL_BIN" -i -c exit > /dev/null 2>&1 || true
    end=$(date +%s%N)
    ms=$(((end - start) / 1000000))
  fi
  [ -n "$ms" ] || {
    echo "startup-budget: could not time the shell — nothing was measured" >&2
    exit 1
  }
  times="$times$ms
"
done

median=$(printf '%s' "$times" | sort -n | awk 'NF{a[n++]=$1} END{print a[int(n/2)]}')

[ -n "$median" ] || {
  echo "startup-budget: no timings collected — nothing was measured" >&2
  exit 1
}

if [ "$median" -gt "$CEILING" ]; then
  echo "$SHELL_BIN -i -c exit: ${median} ms median of $RUNS (ceiling ${CEILING} ms)"
  echo ""
  echo "Startup got structurally slower, not just noisy. Find which eval:"
  echo "  for t in sheldon atuin mise starship fzf zoxide; do …  # see zsh/30-plugins.zsh"
  echo "Then either cut it, defer it, or re-measure and move the ceiling deliberately."
  exit 1
fi

echo "ok shell startup (${median} ms median of $RUNS, ceiling ${CEILING} ms)"
