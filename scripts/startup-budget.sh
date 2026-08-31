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
_median_of_runs() { # -> prints the median startup in ms, or empty on failure
  _i=0
  _times=''
  while [ "$_i" -lt "$RUNS" ]; do
    _i=$((_i + 1))
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
    [ -n "$ms" ] || return 1
    _times="$_times$ms
"
  done
  printf '%s' "$_times" | sort -n | awk 'NF{a[n++]=$1} END{print a[int(n/2)]}'
}

# RETRY THE WHOLE MEASUREMENT, up to ATTEMPTS times, passing on the first one
# under the ceiling.
#
# The median of 5 above already absorbs a single scheduler hiccup. It does not
# absorb SUSTAINED load, which moves all five together — measured on this
# machine while it was running several agents: 532/665/693/647/632/650 ms
# against a 450 ms ceiling, with the same shell measuring 238 ms once the
# machine was quiet. A structural regression and a busy laptop were
# indistinguishable, and this check is wired to `boom verify` on a nightly timer
# with `notify = true`.
#
# That is the failure `boomfile.toml` already paid for once with the MCP health
# check, which was given a three-read retry because "a check that cries wolf is
# worse than no check". Same remedy, same reason: a check whose notification is
# wrong more often than right trains you to dismiss the one that matters.
#
# It does not weaken the signal. A shell that is genuinely slower is slower on
# every attempt, so a real regression still fails all three; only a transient
# spike is forgiven, and forgiving it is the entire point.
ATTEMPTS=${STARTUP_ATTEMPTS:-3}
attempt=0
median=''
while [ "$attempt" -lt "$ATTEMPTS" ]; do
  attempt=$((attempt + 1))
  median=$(_median_of_runs) || {
    echo "startup-budget: could not time the shell — nothing was measured" >&2
    exit 1
  }
  [ -n "$median" ] || {
    echo "startup-budget: no timings collected — nothing was measured" >&2
    exit 1
  }
  [ "$median" -gt "$CEILING" ] || break
done

if [ "$median" -gt "$CEILING" ]; then
  echo "$ATTEMPTS attempts, every one over the ceiling — not a load spike."
  echo "$SHELL_BIN -i -c exit: ${median} ms median of $RUNS (ceiling ${CEILING} ms)"
  echo ""
  echo "Startup got structurally slower, not just noisy. Find which eval:"
  echo "  for t in sheldon atuin mise starship fzf zoxide; do …  # see zsh/30-plugins.zsh"
  echo "Then either cut it, defer it, or re-measure and move the ceiling deliberately."
  exit 1
fi

echo "ok shell startup (${median} ms median of $RUNS, ceiling ${CEILING} ms)"
