#!/usr/bin/env bash
# verify-golden.sh — diff (or regenerate) golden fixtures against the current
# shell scripts. Reports PASS/FAIL per fixture; exits non-zero on any mismatch.
#
# Usage:
#   tests/verify-golden.sh           # compare mode: diff scripts vs fixtures
#   tests/verify-golden.sh --update  # update mode: regenerate fixtures from scripts
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
JQDIR=/Users/jarvis/.local/share/mise/installs/jq/1.8.1
TOOLPATH="$JQDIR:/opt/homebrew/bin:/usr/bin:/bin"

REPO=$(git -C "$ROOT" rev-parse --show-toplevel)
HASH=$(printf '%s' "$REPO" | shasum -a 256 | cut -c1-12)

T=$(mktemp -d "${TMPDIR:-/tmp}/vg.XXXXXX")
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/.cache/git-data" "$T/.claude/state/cost" "$T/nonrepo"
printf '{\n  "advisorModel": "claude-haiku-4-5"\n}\n' > "$T/.claude/settings.json"

PASS=0
FAIL=0
declare -a FAILED=()
declare -a UPDATED=()

strip_rate() { LC_ALL=C grep -v $'^\033\[90m[57][hd] ' || true; }
strip_elapsed() { sed 's/"elapsed":"[^"]*"/"elapsed":"ELAPSED"/g'; }

cmp_out() {
  local name="$1"
  local actual="$2"
  local gf="$OUT/${name}.txt"

  if [ "$UPDATE" -eq 1 ]; then
    printf '%s\n' "$actual" > "$gf"
    echo "UPDATED $name"
    UPDATED+=("$name")
    return
  fi

  [ -f "$gf" ] || {
    echo "SKIP $name"
    return
  }
  local g a
  case "$name" in
    statusline-*)
      g=$(strip_rate < "$gf")
      a=$(printf '%s\n' "$actual" | strip_rate)
      ;;
    subagent-*)
      g=$(strip_elapsed < "$gf")
      a=$(printf '%s\n' "$actual" | strip_elapsed)
      ;;
    *)
      g=$(cat "$gf")
      a="$actual"
      ;;
  esac
  if [ "$g" = "$a" ]; then
    echo "PASS $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL $name"
    FAILED+=("$name")
    FAIL=$((FAIL + 1))
    diff <(printf '%s\n' "$g") <(printf '%s\n' "$a") | head -12 || true
  fi
}

run_prompt() {
  local f="$1"
  cp "$GOLDEN/cache/${f}.sh" "$T/.cache/git-data/${HASH}.sh"
  HOME="$T" XDG_CACHE_HOME="$T/.cache" PWD="$REPO" COLUMNS=120 PATH="$TOOLPATH" \
    bash "$ROOT/prompt/prompt-render" 2> /dev/null
}
run_sl() {
  local f="$1"
  rm -rf "$T/.claude/state/cost"
  mkdir -p "$T/.claude/state/cost"
  (cd "$T/nonrepo" && HOME="$T" XDG_CACHE_HOME="$T/.cache" COLUMNS=120 \
    CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=80 PATH="$TOOLPATH" \
    bash "$ROOT/share/claude-statusline/statusline.sh" < "$GOLDEN/json/${f}.json" 2> /dev/null)
}
run_sub() {
  local f="$1"
  (cd "$T/nonrepo" && HOME="$T" XDG_CACHE_HOME="$T/.cache" COLUMNS=168 PATH="$TOOLPATH" \
    bash "$ROOT/share/claude-statusline/subagent-statusline.sh" < "$GOLDEN/subagent/${f}.json" 2> /dev/null)
}

for f in clean-main dirty-feature worktree pr-pass; do
  cmp_out "prompt-${f}" "$(run_prompt "$f")"
done
for f in low-ctx high-ctx-near-ac rate-limits-high with-pr narrow-60 wide-200; do
  cmp_out "statusline-${f}" "$(run_sl "$f")"
done
for f in active-tasks error-state narrow-compact; do
  cmp_out "subagent-${f}" "$(run_sub "$f")"
done

if [ "$UPDATE" -eq 1 ]; then
  echo "Updated ${#UPDATED[@]} fixture(s): ${UPDATED[*]}"
else
  echo "Results: $PASS passed, $FAIL failed"
  [ "${#FAILED[@]}" -eq 0 ] || printf 'FAILED: %s\n' "${FAILED[*]}"
  [ "$FAIL" -eq 0 ]
fi
