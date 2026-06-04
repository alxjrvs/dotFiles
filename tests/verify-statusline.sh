#!/usr/bin/env bash
# verify-statusline.sh — compares statusline port output to goldens using temp
# files (no process substitution, sandbox-safe). Strips rate-limit rows exactly
# like run-golden.sh.
set -euo pipefail

ROOT=/Users/jarvis/Code/dotFiles/.claude/worktrees/dedotctl
GOLDEN="$ROOT/tests/golden"
OUT="$GOLDEN/out"
JQDIR=/Users/jarvis/.local/share/mise/installs/jq/1.8.1
TOOLPATH="$JQDIR:/opt/homebrew/bin:/usr/bin:/bin"

T=$(mktemp -d "${TMPDIR:-/tmp}/vsl.XXXXXX")
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/.cache/git-data" "$T/.claude/state/cost" "$T/nonrepo"
printf '{\n  "advisorModel": "claude-haiku-4-5"\n}\n' > "$T/.claude/settings.json"

strip_rate() { LC_ALL=C grep -v $'^\033\[90m[57][hd] ' || true; }

PASS=0
FAIL=0
for f in low-ctx high-ctx-near-ac rate-limits-high with-pr narrow-60 wide-200; do
  rm -rf "$T/.claude/state/cost"
  mkdir -p "$T/.claude/state/cost"
  actual=$(cd "$T/nonrepo" && HOME="$T" XDG_CACHE_HOME="$T/.cache" COLUMNS=120 \
    CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=80 PATH="$TOOLPATH" \
    bash "$ROOT/share/claude-statusline/statusline.sh" < "$GOLDEN/json/${f}.json" 2> /dev/null)
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
echo "statusline: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
