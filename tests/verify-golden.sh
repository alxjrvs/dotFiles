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
# jq lives wherever mise put it (version changes on every bump) — resolve it,
# don't hardcode the install path. Falls back to any jq on PATH.
JQBIN="$(mise which jq 2> /dev/null || command -v jq || true)"
if [[ -z "$JQBIN" ]]; then
  echo "ERROR: jq not found (mise which jq / PATH) — cannot run renderers" >&2
  exit 2
fi
TOOLPATH="$(dirname "$JQBIN"):/opt/homebrew/bin:/usr/bin:/bin"

REPO=$(git -C "$ROOT" rev-parse --show-toplevel)
# Cache key: run the canonical repo_hash extracted from git-data itself, so
# the harness can never drift from the producer's hash function.
HASH=$(bash -c "$(sed -n '/^repo_hash() {/,/^}/p' "$ROOT/prompt/git-data"); repo_hash \"\$1\"" _ "$REPO")
[[ "$HASH" =~ ^[0-9a-f]{12}$ ]] || {
  echo "ERROR: repo_hash extraction from prompt/git-data failed" >&2
  exit 2
}

T=$(mktemp -d "${TMPDIR:-/tmp}/vg.XXXXXX")
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/.cache/git-data" "$T/.claude/state/cost" "$T/nonrepo"
printf '{\n  "advisorModel": "claude-haiku-4-5"\n}\n' > "$T/.claude/settings.json"

PASS=0
FAIL=0
declare -a FAILED=()
declare -a UPDATED=()

# Rate-limit rows (5h / 7d) carry a "[Xh Ym left]" label computed from
# `resets_at - now` — time-dependent, so they're stripped before diffing.
# Matching is plain shell `case` globbing on the exact ANSI prefix the
# statusline emits: no grep, so no regex-engine drift (the previous grep
# pattern silently matched nothing under both BSD grep and ugrep).
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
      # Self-check: a golden whose rows carry the time label must yield
      # strips, or the ANSI prefix has drifted and the "stripped" diff would
      # silently compare time-dependent text (flaky) — fail loudly instead.
      local gn
      gn=$(rate_count < "$gf")
      if [ "$gn" -eq 0 ] && [ -n "$(cat "$gf")" ]; then
        case "$(cat "$gf")" in
          *" left"*)
            echo "ERROR: $name golden has rate-limit rows but strip matched none — update RATE5/RATE7 prefixes" >&2
            exit 2
            ;;
        esac
      fi
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
  # Unset git-discovery env vars so the statusline git segment reflects the
  # non-repo cwd, not an ambient repo. git honors GIT_DIR/GIT_INDEX_FILE over
  # the working directory, and a `git push` pre-push hook exports both — without
  # this the fixtures render the live repo and every statusline golden mismatches.
  (cd "$T/nonrepo" &&
    unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_COMMON_DIR GIT_PREFIX &&
    HOME="$T" XDG_CACHE_HOME="$T/.cache" COLUMNS=120 \
      CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=80 PATH="$TOOLPATH" \
      bash "$ROOT/share/claude-statusline/statusline.sh" < "$GOLDEN/json/${f}.json" 2> /dev/null)
}
run_sub() {
  local f="$1"
  (cd "$T/nonrepo" &&
    unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_COMMON_DIR GIT_PREFIX &&
    HOME="$T" XDG_CACHE_HOME="$T/.cache" COLUMNS=168 PATH="$TOOLPATH" \
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
