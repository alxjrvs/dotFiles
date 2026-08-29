#!/usr/bin/env sh
# Fake `launchctl print` for scripts/tests/gates.sh.
#
# schedule-health.sh reads two fields out of launchd — `runs` and `last exit
# code` — and the three incidents it exists to catch are all combinations of
# them. Driving the real launchctl in a test would assert whatever this machine
# happens to be doing today, which is the opposite of a regression test, so the
# script takes PRINT_CMD and this stands in.
#
# $1 = label. FIXTURE_MODE picks which failure to reproduce.
set -eu

label=${1:-}

case "${FIXTURE_MODE:-healthy}" in
  healthy)
    printf '\tstate = not running\n\truns = 44\n\tlast exit code = 0\n'
    ;;
  failing)
    # `git maintenance` against paths that no longer existed: fired on schedule,
    # exited 1 every single time, indefinitely.
    printf '\tstate = not running\n\truns = 217\n\tlast exit code = 1\n'
    ;;
  never-ran)
    # boom-verify behind an unexpanded `~`: registered, scheduled, runs = 0 for
    # 28 days. Reported, not failed — a freshly provisioned machine looks the
    # same, and a check that cries wolf on day one is bypassed by day two.
    printf '\tstate = not running\n\truns = 0\n'
    ;;
  absent)
    # Declared in this repo, not loaded on the machine at all.
    printf ''
    ;;
  *)
    echo "launchctl-print fixture: unknown FIXTURE_MODE for $label" >&2
    exit 2
    ;;
esac
