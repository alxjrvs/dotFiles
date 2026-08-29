#!/usr/bin/env sh
# Every scheduled job on this machine has run, and its last run succeeded.
#
# WHY THIS EXISTS, AND WHY IT IS A CLASS AND NOT A CHECK. This repo has three
# separate recorded incidents of the same shape — a launchd job that was
# registered, fired, failed, and reported only into a log nobody reads:
#
#   - The nightly `boom verify` timer never ran for 28 days. A `~` in a plist path
#     value, which launchd does not expand, so the job died with EX_CONFIG (78)
#     before executing. Every guardrail it carried sat un-run, and `notify = true`
#     never fired because nothing ran to notify.
#   - `code reap --push` recorded 0 successful pushes against 84 failures over 14
#     sweeps. The flag was removed once someone finally read the log.
#   - `git maintenance` was registered against two paths that no longer exist, so
#     all three org.git-scm.git.* agents exited 1 on every fire, indefinitely.
#
# Each was found by hand and fixed individually. Nothing owned the CLASS, so the
# next instance was always going to be found the same way — late, and by luck.
# `plist-validity.sh` catches one specific cause (the `~`); this catches the
# symptom regardless of cause, which is the half that generalises.
#
# WHY THE SYMPTOM IS THE RIGHT THING TO ASSERT. A scheduled job has exactly two
# observable failure modes and launchd reports both: it never ran (`runs = 0`),
# or its last run failed (`last exit code != 0`). Neither depends on knowing why.
# A future job that fails for a reason nobody has thought of still trips this.
#
# WHAT IT WOULD HAVE CAUGHT. All three incidents above, on the first nightly
# verify after they started.
#
# SCOPED to the jobs this configuration owns: boom's own scheduled timers
# (`com.boomtube.*`, generated from `[boom].schedule`) and the plists in
# launchd/. Anything else on the machine belongs to someone else.
#
# Usage: scripts/schedule-health.sh
set -eu

LAUNCHD_DIR=${LAUNCHD_DIR:-launchd}
# Both overridable so the regression suite can drive a fixture instead of the
# machine: PRINT_CMD stands in for `launchctl print` (one job's status), LIST_CMD
# for `launchctl list` (which boom timers exist). Testing against the real
# launchd would assert whatever this machine happens to be doing today, which is
# the opposite of a regression test.
PRINT_CMD=${PRINT_CMD:-}
LIST_CMD=${LIST_CMD:-}

uid=$(id -u)

labels=''

# boom's generated timers. `launchctl list` is the enumeration that does not
# require knowing the names in advance — which matters, because they come from
# `[boom].schedule` and change when that does.
if [ -n "$LIST_CMD" ]; then
  boom_labels=$($LIST_CMD 2> /dev/null | awk '$3 ~ /^com\.boomtube\./ { print $3 }' || true)
  labels="$labels $boom_labels"
elif command -v launchctl > /dev/null 2>&1; then
  boom_labels=$(launchctl list 2> /dev/null | awk '$3 ~ /^com\.boomtube\./ { print $3 }' || true)
  labels="$labels $boom_labels"
fi

# The hand-written plists this repo installs. Read from the FILES, not from
# launchd: a plist that was never loaded at all is exactly the failure this is
# looking for, and enumerating from launchd would make it invisible.
if [ -d "$LAUNCHD_DIR" ]; then
  for p in "$LAUNCHD_DIR"/*.plist; do
    [ -e "$p" ] || continue
    l=$(basename "$p" .plist)
    labels="$labels $l"
  done
fi

# shellcheck disable=SC2086
set -- $labels
[ "$#" -gt 0 ] || {
  echo "schedule-health: no scheduled jobs found — this check asserted nothing" >&2
  exit 1
}

fail=0
checked=0

for label in "$@"; do
  [ -n "$label" ] || continue
  checked=$((checked + 1))

  if [ -n "$PRINT_CMD" ]; then
    out=$($PRINT_CMD "$label" 2> /dev/null || true)
  else
    out=$(launchctl print "gui/$uid/$label" 2> /dev/null || true)
  fi

  if [ -z "$out" ]; then
    echo "$label: not loaded in launchd (declared here, absent on the machine)"
    fail=1
    continue
  fi

  runs=$(printf '%s\n' "$out" | awk '/^[[:space:]]*runs =/ { print $3; exit }')
  code=$(printf '%s\n' "$out" | awk '/^[[:space:]]*last exit code =/ { print $5; exit }')

  # A RunAtLoad agent that is currently running has no completed run yet, and a
  # timer installed minutes ago legitimately has runs = 0. Report those rather
  # than failing: this check must not cry wolf on a freshly-provisioned machine,
  # because a check that is noisy on day one gets bypassed by day two — which is
  # the failure this repo has already paid for twice.
  if [ -z "$runs" ] || [ "$runs" = "0" ]; then
    echo "note $label: registered but has never run yet"
    continue
  fi

  if [ -z "$code" ]; then
    echo "note $label: $runs run(s), no exit status reported"
    continue
  fi

  if [ "$code" = "0" ]; then
    echo "ok $label ($runs runs, last exit 0)"
  else
    echo "$label: $runs run(s), LAST EXIT $code — it is firing and failing"
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "A scheduled job that fires and fails reports only into its own log,"
  echo "which is how boom-verify sat dead for 28 days and code-reap --push"
  echo "recorded 0 successes against 84 failures. Read the job's log:"
  echo "  ~/.local/state/boom/logs/<label>.log      (boom timers)"
  echo "  launchctl print gui/$uid/<label>          (status, exit code, runs)"
  exit 1
fi

echo "ok schedule-health ($checked scheduled job(s))"
