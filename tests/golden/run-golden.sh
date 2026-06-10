#!/usr/bin/env bash
# run-golden.sh — parametrized capture/compare driver for golden tests.
#
# USAGE
#   Capture mode (record new goldens from a binary):
#     ./run-golden.sh capture [binary-prefix]
#     binary-prefix defaults to "dot" (must be on PATH or an absolute path)
#
#   Compare mode (verify a binary produces byte-identical output):
#     ./run-golden.sh compare [binary-prefix]
#
#   Single fixture:
#     ./run-golden.sh capture dot prompt-clean-main
#     ./run-golden.sh compare dot prompt-clean-main
#
# EXIT CODES
#   0 — all comparisons passed (or capture completed)
#   1 — one or more comparisons failed
#
# NOTES ON TIME-DEPENDENT FIELDS
#   Statusline lines 4-5 ("5h" and "7d" rate-limit rows) contain a
#   "[Xh Ym left]" time label computed from `resets_at - now`. These are
#   NOT strictly comparable — the harness strips them before diffing.
#
#   Statusline line 6 ("today $X") appears ONLY when cross-session cost
#   files exist. The harness uses a clean temp HOME so only the per-session
#   "$cost" portion appears — that IS strictly comparable.
#
#   Subagent "elapsed" fields are computed from `startTime - now_ms`. These
#   are NOT strictly comparable. The harness strips the elapsed field from
#   JSON output before diffing.
#
#   Prompt-render output is fully deterministic — all fields strictly comparable.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GOLDEN_DIR="$SCRIPT_DIR"
CACHE_DIR="$GOLDEN_DIR/cache"
JSON_DIR="$GOLDEN_DIR/json"
SUBAGENT_DIR="$GOLDEN_DIR/subagent"
OUT_DIR="$GOLDEN_DIR/out"

MODE="${1:-compare}"
BINARY="${2:-dot}"
SINGLE_FIXTURE="${3:-}"

# ── Resolve the repo toplevel (for prompt-render: must run from inside it) ──
# The prompt-render/statusline hot paths call load_cache() which runs
# `git rev-parse --show-toplevel` from CWD. Running from the dotfiles worktree
# ensures the correct repo hash is computed.
DOTFILES_WORKTREE="$SCRIPT_DIR/../.."
REPO_TOPLEVEL=$(git -C "$DOTFILES_WORKTREE" rev-parse --show-toplevel 2> /dev/null || echo "")
if [[ -z "$REPO_TOPLEVEL" ]]; then
  echo "ERROR: could not resolve repo toplevel from $DOTFILES_WORKTREE" >&2
  exit 1
fi

# ── Repo hash (12-hex cache key) ──
# Run the canonical repo_hash extracted from prompt/git-data itself, so the
# harness can never drift from the producer's hash function.
repo_hash() {
  bash -c "$(sed -n '/^repo_hash() {/,/^}/p' "$DOTFILES_WORKTREE/prompt/git-data"); repo_hash \"\$1\"" _ "$1"
}
REPO_HASH=$(repo_hash "$REPO_TOPLEVEL")
[[ "$REPO_HASH" =~ ^[0-9a-f]{12}$ ]] || {
  echo "ERROR: repo_hash extraction from prompt/git-data failed" >&2
  exit 1
}

# ── Pinned test environment ──
TMPDIR_TEST="${TMPDIR:-/tmp}/golden-harness-$$"
mkdir -p "$TMPDIR_TEST"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

mkdir -p "$TMPDIR_TEST/.cache/git-data"
mkdir -p "$TMPDIR_TEST/.claude/state/cost"
cat > "$TMPDIR_TEST/.claude/settings.json" << 'EOF'
{
  "advisorModel": "claude-haiku-4-5"
}
EOF

# Strip gh from PATH so the statusline's PR refresh is neutralized. The
# binary's own dir and jq's dir stay reachable (jq lives wherever mise put
# it — resolve, don't hardcode).
if command -v "$BINARY" > /dev/null 2>&1; then
  BIN_DIR="$(dirname "$(command -v "$BINARY")")"
else
  BIN_DIR="$(cd "$(dirname "$BINARY")" && pwd)"
fi
JQBIN="$(mise which jq 2> /dev/null || command -v jq || true)"
if [[ -z "$JQBIN" ]]; then
  echo "ERROR: jq not found (mise which jq / PATH)" >&2
  exit 1
fi
SAFE_PATH="$BIN_DIR:$(dirname "$JQBIN"):/usr/bin:/bin:/usr/local/bin"

PASS=0
FAIL=0

# ── Helper: run prompt-render with a named cache fixture ──
run_prompt_render() {
  local fixture_name="$1" # e.g. "clean-main"
  local cache_src="$CACHE_DIR/${fixture_name}.sh"
  local cache_dst="$TMPDIR_TEST/.cache/git-data/${REPO_HASH}.sh"

  [[ -f "$cache_src" ]] || {
    echo "SKIP: cache fixture $fixture_name not found"
    return
  }
  cp "$cache_src" "$cache_dst"
  chmod 600 "$cache_dst"

  HOME="$TMPDIR_TEST" \
    XDG_CACHE_HOME="$TMPDIR_TEST/.cache" \
    PWD="$REPO_TOPLEVEL" \
    COLUMNS=120 \
    PATH="$SAFE_PATH" \
    "$BINARY" prompt-render 2>&1
}

# ── Helper: run statusline with a named JSON fixture ──
# Runs from a non-repo temp dir so git_data::run() finds no repo (deterministic
# line 1 — just the project_dir from the JSON, no live git counters).
run_statusline() {
  local fixture_name="$1" # e.g. "low-ctx"
  local json_src="$JSON_DIR/${fixture_name}.json"

  [[ -f "$json_src" ]] || {
    echo "SKIP: json fixture $fixture_name not found"
    return
  }

  # Clean cost dir so each run starts fresh (no cross-session "today" total).
  rm -rf "$TMPDIR_TEST/.claude/state/cost"
  mkdir -p "$TMPDIR_TEST/.claude/state/cost"

  local nonrepo_dir="$TMPDIR_TEST/nonrepo"
  mkdir -p "$nonrepo_dir"

  (cd "$nonrepo_dir" &&
    HOME="$TMPDIR_TEST" \
      XDG_CACHE_HOME="$TMPDIR_TEST/.cache" \
      COLUMNS=120 \
      CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=80 \
      PATH="$SAFE_PATH" \
      "$BINARY" statusline < "$json_src" 2>&1)
}

# ── Helper: run subagent-statusline with a named subagent fixture ──
run_subagent_statusline() {
  local fixture_name="$1" # e.g. "active-tasks"
  local json_src="$SUBAGENT_DIR/${fixture_name}.json"

  [[ -f "$json_src" ]] || {
    echo "SKIP: subagent fixture $fixture_name not found"
    return
  }

  local nonrepo_dir="$TMPDIR_TEST/nonrepo"
  mkdir -p "$nonrepo_dir"

  (cd "$nonrepo_dir" &&
    HOME="$TMPDIR_TEST" \
      XDG_CACHE_HOME="$TMPDIR_TEST/.cache" \
      COLUMNS=168 \
      PATH="$SAFE_PATH" \
      "$BINARY" subagent-statusline < "$json_src" 2>&1)
}

# ── Strip time-dependent lines before compare ──
# Statusline lines 4-5 (5h / 7d rate-limit rows) contain the clock pip AND
# "[Xh Ym left]" label — BOTH depend on `now - resets_at`. Remove those lines
# entirely; lines 1-3 (git context, model, CTX bar) and line 6 (cost) are
# strictly comparable.
#
# Rate-limit rows are identified by the ANSI-grey "5h " / "7d " prefix the
# statusline emits: ESC[90m<label> at column 0. Matched with plain shell
# `case` globbing — no grep, so no regex-engine drift (the previous grep
# pattern silently matched nothing under both BSD grep and ugrep).
RATE5=$'\033[90m5h '
RATE7=$'\033[90m7d '
strip_rate_limit_rows() {
  local line
  while IFS= read -r line; do
    case "$line" in
      "$RATE5"* | "$RATE7"*) ;;
      *) printf '%s\n' "$line" ;;
    esac
  done
}

# Subagent: remove "elapsed" JSON field value (keep key, zero out value to "0s").
# We diff the full JSON structure (state, tokenText, queuedCount, tokenSamples)
# but not the elapsed string.
strip_elapsed() {
  sed 's/"elapsed":"[^"]*"/"elapsed":"ELAPSED"/g'
}

# ── Compare one output ──
compare_output() {
  local name="$1"
  local actual="$2"
  local golden_file="$OUT_DIR/${name}.txt"

  if [[ ! -f "$golden_file" ]]; then
    echo "SKIP: no golden for $name"
    return
  fi

  local golden_stripped actual_stripped
  if [[ "$name" == statusline-* ]]; then
    golden_stripped=$(strip_rate_limit_rows < "$golden_file")
    actual_stripped=$(printf '%s\n' "$actual" | strip_rate_limit_rows)
  elif [[ "$name" == subagent-* ]]; then
    golden_stripped=$(strip_elapsed < "$golden_file")
    actual_stripped=$(printf '%s\n' "$actual" | strip_elapsed)
  else
    golden_stripped=$(cat "$golden_file")
    actual_stripped="$actual"
  fi

  local tmp_golden tmp_actual
  tmp_golden="$TMPDIR_TEST/diff-golden-$$"
  tmp_actual="$TMPDIR_TEST/diff-actual-$$"
  printf '%s\n' "$golden_stripped" > "$tmp_golden"
  printf '%s\n' "$actual_stripped" > "$tmp_actual"

  if diff "$tmp_golden" "$tmp_actual" > /dev/null 2>&1; then
    echo "PASS: $name"
    ((PASS++)) || true
  else
    echo "FAIL: $name"
    diff "$tmp_golden" "$tmp_actual" | head -20 || true
    ((FAIL++)) || true
  fi
  rm -f "$tmp_golden" "$tmp_actual"
}

# ── Fixture lists ──
PROMPT_FIXTURES=(clean-main dirty-feature worktree pr-pass)
STATUSLINE_FIXTURES=(low-ctx high-ctx-near-ac rate-limits-high with-pr narrow-60 wide-200)
SUBAGENT_FIXTURES=(active-tasks error-state narrow-compact)

# ── Filter to single fixture if requested ──
filter_fixture() {
  local prefix="$1"
  local fixture="$2"
  if [[ -n "$SINGLE_FIXTURE" && "$prefix-$fixture" != "$SINGLE_FIXTURE" && "$fixture" != "$SINGLE_FIXTURE" ]]; then
    return 1
  fi
  return 0
}

# ── Main ──
case "$MODE" in
  capture)
    echo "Capturing golden outputs with binary: $BINARY"
    echo "Repo toplevel: $REPO_TOPLEVEL (hash: $REPO_HASH)"
    echo ""

    for f in "${PROMPT_FIXTURES[@]}"; do
      filter_fixture prompt "$f" || continue
      out=$(run_prompt_render "$f")
      printf '%s\n' "$out" > "$OUT_DIR/prompt-${f}.txt"
      echo "Captured: prompt-${f}.txt"
    done

    for f in "${STATUSLINE_FIXTURES[@]}"; do
      filter_fixture statusline "$f" || continue
      out=$(run_statusline "$f")
      printf '%s\n' "$out" > "$OUT_DIR/statusline-${f}.txt"
      echo "Captured: statusline-${f}.txt"
    done

    for f in "${SUBAGENT_FIXTURES[@]}"; do
      filter_fixture subagent "$f" || continue
      out=$(run_subagent_statusline "$f")
      printf '%s\n' "$out" > "$OUT_DIR/subagent-${f}.txt"
      echo "Captured: subagent-${f}.txt"
    done

    echo ""
    echo "Done. Golden outputs written to $OUT_DIR/"
    echo "NOTE: subagent elapsed fields are time-dependent — re-run verify"
    echo "      against the shell port soon after capture for accurate deltas."
    ;;

  compare)
    echo "Comparing outputs from binary: $BINARY"
    echo "Repo toplevel: $REPO_TOPLEVEL (hash: $REPO_HASH)"
    echo ""

    for f in "${PROMPT_FIXTURES[@]}"; do
      filter_fixture prompt "$f" || continue
      out=$(run_prompt_render "$f")
      compare_output "prompt-${f}" "$out"
    done

    for f in "${STATUSLINE_FIXTURES[@]}"; do
      filter_fixture statusline "$f" || continue
      out=$(run_statusline "$f")
      compare_output "statusline-${f}" "$out"
    done

    for f in "${SUBAGENT_FIXTURES[@]}"; do
      filter_fixture subagent "$f" || continue
      out=$(run_subagent_statusline "$f")
      compare_output "subagent-${f}" "$out"
    done

    echo ""
    echo "Results: $PASS passed, $FAIL failed"
    [[ "$FAIL" -eq 0 ]]
    ;;

  *)
    echo "Usage: $0 capture|compare [binary] [fixture]" >&2
    exit 1
    ;;
esac
