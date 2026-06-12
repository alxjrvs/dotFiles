#!/usr/bin/env bash
# verify-statusline.sh — diff (or regenerate) statusline golden fixtures against
# the current shell scripts, using temp files (no process substitution).
# Strips rate-limit rows exactly like run-golden.sh.
#
# Usage:
#   tests/verify-statusline.sh           # compare mode: diff scripts vs fixtures
#   tests/verify-statusline.sh --update  # update mode: regenerate fixtures from scripts
set -euo pipefail

UPDATE=0
for arg in "$@"; do
  case "$arg" in
    --update) UPDATE=1 ;;
    *)
      echo "unknown arg: $arg" >&2
      exit 1
      ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GOLDEN="$ROOT/tests/golden"
OUT="$GOLDEN/out"
# jq lives wherever mise put it (version changes on every bump) — resolve it,
# don't hardcode the install path. Falls back to any jq on PATH.
JQBIN="$(mise which jq 2> /dev/null || command -v jq || true)"
if [[ -z "$JQBIN" ]]; then
  echo "ERROR: jq not found (mise which jq / PATH) — cannot run statusline" >&2
  exit 2
fi
TOOLPATH="$(dirname "$JQBIN"):/opt/homebrew/bin:/usr/bin:/bin"

T=$(mktemp -d "${TMPDIR:-/tmp}/vsl.XXXXXX")
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/.cache/git-data" "$T/.claude" "$T/nonrepo"
printf '{\n  "advisorModel": "claude-haiku-4-5"\n}\n' > "$T/.claude/settings.json"

# Strip the time-dependent 5h/7d rate-limit rows by exact ANSI prefix, via
# shell `case` globbing — no grep, no regex-engine drift (the previous grep
# pattern silently matched nothing). rate_count feeds the self-check below.
RATE5=$'\033[90m5h '
RATE7=$'\033[90m7d '
strip_rate() {
  local line
  while IFS= read -r line; do
    case "$line" in
      "$RATE5"* | "$RATE7"*) ;;
      *) printf '%s\n' "$line" ;;
    esac
  done
}
rate_count() {
  local line n=0
  while IFS= read -r line; do
    case "$line" in
      "$RATE5"* | "$RATE7"*) n=$((n + 1)) ;;
    esac
  done
  echo "$n"
}

PASS=0
FAIL=0
declare -a UPDATED=()

for f in low-ctx high-ctx-near-ac rate-limits-high with-pr narrow-60 wide-200; do
  actual=$(cd "$T/nonrepo" && HOME="$T" XDG_CACHE_HOME="$T/.cache" COLUMNS=120 \
    CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=80 PATH="$TOOLPATH" \
    bash "$ROOT/share/claude-statusline/statusline.sh" < "$GOLDEN/json/${f}.json" 2> /dev/null)

  if [ "$UPDATE" -eq 1 ]; then
    printf '%s\n' "$actual" > "$OUT/statusline-${f}.txt"
    echo "UPDATED statusline-$f"
    UPDATED+=("statusline-$f")
    continue
  fi

  # Self-check: a golden carrying the "[Xh Ym left]" label must yield strips,
  # or the ANSI prefix has drifted and the diff would silently compare
  # time-dependent text (flaky) — fail loudly instead.
  gn=$(rate_count < "$OUT/statusline-${f}.txt")
  if [ "$gn" -eq 0 ]; then
    case "$(cat "$OUT/statusline-${f}.txt")" in
      *" left"*)
        echo "ERROR: statusline-$f golden has rate-limit rows but strip matched none — update RATE5/RATE7 prefixes" >&2
        exit 2
        ;;
    esac
  fi
  printf '%s\n' "$actual" | strip_rate > "$T/actual.txt"
  strip_rate < "$OUT/statusline-${f}.txt" > "$T/golden.txt"
  if diff -u "$T/golden.txt" "$T/actual.txt" > "$T/diff.txt" 2>&1; then
    echo "PASS statusline-$f"
    PASS=$((PASS + 1))
  else
    echo "FAIL statusline-$f"
    cat -v "$T/diff.txt" | head -25
    FAIL=$((FAIL + 1))
  fi
done

if [ "$UPDATE" -eq 1 ]; then
  echo "Updated ${#UPDATED[@]} fixture(s): ${UPDATED[*]}"
else
  echo "statusline: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ]
fi
