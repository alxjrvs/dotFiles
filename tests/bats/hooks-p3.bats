#!/usr/bin/env bats
# Unit tests for the P3 follow-up hooks: precompact, subagent-stop,
# the per-session sharding of stop, and byte-safety of trim-bash-output.
# HOME is pointed at a temp dir so ledger/shard writes never touch the real
# ~/.claude/state.

ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
JQDIR="$(dirname "$(mise which jq 2> /dev/null || command -v jq)")"
# Resolved at file scope (real HOME): once setup() fakes HOME, `mise which`
# can no longer see the real installs, so the format-on-save tests put these
# dirs on PATH and the hook reaches the tools via its command -v fallback.
SHFMTDIR="$(dirname "$(mise which shfmt 2> /dev/null || command -v shfmt 2> /dev/null || echo /nonexistent/shfmt)")"
SHELLCHECKDIR="$(dirname "$(mise which shellcheck 2> /dev/null || command -v shellcheck 2> /dev/null || echo /nonexistent/shellcheck)")"
PRETTIERDIR="$(dirname "$(mise which prettier 2> /dev/null || command -v prettier 2> /dev/null || echo /nonexistent/prettier)")"

load 'helpers'

setup() {
  scrub_git_env
  export PATH="$JQDIR:/opt/homebrew/bin:/usr/bin:/bin"
  TDIR="$(mktemp -d "${TMPDIR:-/tmp}/bats.XXXXXX")"
  export HOME="$TDIR"
  mkdir -p "$HOME/.claude/state"
}
teardown() { rm -rf "$TDIR"; }

# Helper: run a hook with a JSON payload on stdin.
run_hook() {
  local hook="$1" json="$2"
  printf '%s' "$json" | "$ROOT/hooks/$hook"
}

# ── precompact ──────────────────────────────────────────────────────────────
@test "precompact: exits 0 and appends to the snapshots ledger" {
  local ledger="$HOME/.claude/state/precompact-snapshots.jsonl"
  run run_hook precompact '{"session_id":"sess-1","transcript_path":"/t/x.jsonl","trigger":"auto","cwd":"/repo"}'
  [ "$status" -eq 0 ]
  [ -f "$ledger" ]
  [ "$(wc -l < "$ledger" | tr -d ' ')" -eq 1 ]
  run cat "$ledger"
  [[ "$output" == *'"session_id":"sess-1"'* ]]
  [[ "$output" == *'"trigger":"auto"'* ]]
}

@test "precompact: never blocks (exits 0 on empty/partial payload)" {
  run run_hook precompact '{}'
  [ "$status" -eq 0 ]
  # A second invocation appends rather than truncating.
  run run_hook precompact '{"session_id":"sess-2","trigger":"manual"}'
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$HOME/.claude/state/precompact-snapshots.jsonl" | tr -d ' ')" -eq 2 ]
}

# ── subagent-stop ───────────────────────────────────────────────────────────
@test "subagent-stop: exits 0 and appends a ledger line" {
  local ledger="$HOME/.claude/state/subagent-ledger.jsonl"
  run run_hook subagent-stop '{"session_id":"sess-3","agent_type":"explore","cwd":"/repo"}'
  [ "$status" -eq 0 ]
  [ -f "$ledger" ]
  [ "$(wc -l < "$ledger" | tr -d ' ')" -eq 1 ]
  run cat "$ledger"
  [[ "$output" == *'"session_id":"sess-3"'* ]]
  [[ "$output" == *'"task":"explore"'* ]]
}

@test "subagent-stop: falls back to agent_id when agent_type absent" {
  run run_hook subagent-stop '{"session_id":"sess-4","agent_id":"ag-99"}'
  [ "$status" -eq 0 ]
  run cat "$HOME/.claude/state/subagent-ledger.jsonl"
  [[ "$output" == *'"task":"ag-99"'* ]]
}

# ── stop: per-session sharding ──────────────────────────────────────────────
@test "stop: writes to the per-session shard, not a flat sessions.jsonl" {
  run run_hook stop '{"session_id":"abc123","cwd":"/repo","transcript_path":"/t/x.jsonl"}'
  [ "$status" -eq 0 ]
  [ -f "$HOME/.claude/state/sessions/abc123.jsonl" ]
  # The old flat ledger must NOT be created.
  [ ! -e "$HOME/.claude/state/sessions.jsonl" ]
  run cat "$HOME/.claude/state/sessions/abc123.jsonl"
  [[ "$output" == *'"session_id":"abc123"'* ]]
}

@test "stop: falls back to unknown.jsonl when session_id and transcript absent" {
  run run_hook stop '{"cwd":"/repo"}'
  [ "$status" -eq 0 ]
  [ -f "$HOME/.claude/state/sessions/unknown.jsonl" ]
}

@test "stop: derives shard from transcript basename when session_id absent" {
  run run_hook stop '{"cwd":"/repo","transcript_path":"/t/bar.jsonl"}'
  [ "$status" -eq 0 ]
  [ -f "$HOME/.claude/state/sessions/bar.jsonl" ]
}

# ── trim-bash-output: byte safety + threshold ───────────────────────────────
# Guard against any regression that re-introduces the locale-unsafe
# `rev | cut | rev` pipeline removed in favor of head -c / tail -c.
@test "trim-bash-output: no rev dependency remains (no non-comment invocation)" {
  local hits
  # Strip comment lines before grepping: `rev` is mentioned in an explanatory
  # comment but must never be invoked.
  hits=$(grep -vE '^[[:space:]]*#' "$ROOT/hooks/trim-bash-output" | grep -cE '\brev\b' || true)
  [ "$hits" -eq 0 ]
}

@test "trim-bash-output: small output is a silent no-op" {
  run run_hook trim-bash-output '{"tool_name":"Bash","tool_response":{"stdout":"hello"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "trim-bash-output: oversized single-line output is trimmed" {
  # Build a >20KB single-line stdout payload via jq so quoting is safe.
  local big payload
  big=$(printf 'x%.0s' $(seq 1 30000))
  payload=$(jq -cn --arg s "$big" '{tool_name:"Bash",tool_response:{stdout:$s}}')
  run bash -c 'printf "%s" "$1" | "$2/hooks/trim-bash-output"' _ "$payload" "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"trim-bash-output: elided"* ]]
  # Trimmed result must be far smaller than the 30KB input.
  [ "${#output}" -lt 20000 ]
}

@test "trim-bash-output: invalid/multibyte UTF-8 bytes do not error" {
  # Construct a >20KB payload containing raw bytes that are not valid UTF-8
  # (0xFF, 0xFE) plus a multibyte sequence, base64-encoded so it survives the
  # shell, then fed through stdin. jq builds the wrapper JSON from a file slurp.
  local raw="$TDIR/raw.bin" payload="$TDIR/payload.json"
  {
    head -c 25000 /dev/zero | tr '\0' 'A'
    printf '\xff\xfe\xc3\x28\xe2\x82'
    head -c 5000 /dev/zero | tr '\0' 'B'
  } > "$raw"
  # -Rs slurps the (possibly invalid) bytes as a JSON string; jq replaces
  # invalid sequences but must not crash. The hook reads this on stdin.
  jq -Rs '{tool_name:"Bash",tool_response:{stdout:.}}' "$raw" > "$payload" 2> /dev/null || \
    jq -Rs '{tool_name:"Bash",tool_response:{stdout:.}}' < "$raw" > "$payload"
  run bash -c 'cat "$1" | "$2/hooks/trim-bash-output"' _ "$payload" "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"trim-bash-output"* ]]
}

# ── format-on-save: behavioral coverage with real PostToolUse payloads ──────
# The hook once read bare .file_path (never delivered by CC) and was a silent
# no-op for its entire life; these tests pin the real payload shape.

@test "format-on-save: formats a .sh file from a real tool_input payload" {
  [ -x "$SHFMTDIR/shfmt" ] || skip "shfmt unavailable"
  export PATH="$SHFMTDIR:$PATH"
  local f="$TDIR/messy.sh"
  printf '%s\n' '#!/bin/bash' 'if true;then' '      echo hi' 'fi' > "$f"
  run run_hook format-on-save "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\"}}"
  [ "$status" -eq 0 ]
  # shfmt -i 2 -ci -sr normalizes the body to two-space indent + then on its
  # own clause.
  run cat "$f"
  [[ "$output" == *'if true; then'* ]]
  [[ "$output" == *'  echo hi'* ]]
}

@test "format-on-save: tool_response.filePath also resolves" {
  [ -x "$SHFMTDIR/shfmt" ] || skip "shfmt unavailable"
  export PATH="$SHFMTDIR:$PATH"
  local f="$TDIR/messy2.sh"
  printf 'if true;then\necho hi\nfi\n' > "$f"
  run run_hook format-on-save "{\"tool_name\":\"Edit\",\"tool_response\":{\"filePath\":\"$f\"}}"
  [ "$status" -eq 0 ]
  run cat "$f"
  [[ "$output" == *'if true; then'* ]]
}

@test "format-on-save: lint findings arrive in the hookSpecificOutput envelope" {
  [ -x "$SHELLCHECKDIR/shellcheck" ] || skip "shellcheck unavailable"
  export PATH="$SHELLCHECKDIR:$PATH"
  local f="$TDIR/warn.sh"
  # SC2086: unquoted variable — guaranteed shellcheck finding.
  printf '%s\n' '#!/bin/bash' 'v="a b"' 'echo $v' > "$f"
  run run_hook format-on-save "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\"}}"
  [ "$status" -eq 0 ]
  # Envelope shape: documented additionalContext lives inside
  # hookSpecificOutput with the event name.
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "PostToolUse"'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | length > 0'
}

@test "format-on-save: unknown extension is a silent no-op" {
  local f="$TDIR/data.xyz"
  printf 'payload\n' > "$f"
  run run_hook format-on-save "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\"}}"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run cat "$f"
  [[ "$output" == "payload" ]]
}

# ── format-on-save: prettier is project-config-aware ────────────────────────
# Regression for the churn bug: the hook used `prettier --no-config`, which
# reformatted every edited file to prettier DEFAULTS (double quotes + semis),
# fighting repos whose own .prettierrc demands single quotes / no semis. The
# hook must honor the edited file's OWN data-format config, skip entirely when
# there is none (never apply bare defaults), refuse to execute a JS config
# file, and honor .prettierignore.

@test "format-on-save: honors a project .prettierrc.json (single quotes / no semi), not bare defaults" {
  [ -x "$PRETTIERDIR/prettier" ] || skip "prettier unavailable"
  export PATH="$PRETTIERDIR:$PATH"
  mkdir -p "$TDIR/proj/src"
  printf '%s\n' '{ "singleQuote": true, "semi": false }' > "$TDIR/proj/.prettierrc.json"
  local f="$TDIR/proj/src/f.ts"
  printf 'const x = "a";\n' > "$f"
  run run_hook format-on-save "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\"}}"
  [ "$status" -eq 0 ]
  run cat "$f"
  # Config wins: single quotes, no trailing semicolon. (Defaults would yield
  # `const x = "a";` — double quotes + semi.)
  [[ "$output" == "const x = 'a'" ]]
}

@test "format-on-save: skips formatting when the project has no prettier config (no bare defaults)" {
  [ -x "$PRETTIERDIR/prettier" ] || skip "prettier unavailable"
  export PATH="$PRETTIERDIR:$PATH"
  mkdir -p "$TDIR/noconf"
  local f="$TDIR/noconf/f.ts"
  # Deliberately un-prettier-default spacing: if defaults were applied this
  # collapses to `const x = "a";`. Absence of config must leave it untouched.
  printf 'const   x   =   "a"\n' > "$f"
  run run_hook format-on-save "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\"}}"
  [ "$status" -eq 0 ]
  run cat "$f"
  [[ "$output" == 'const   x   =   "a"' ]]
}

@test "format-on-save: refuses to execute a JS prettier config (code-exec vector), leaves file untouched" {
  [ -x "$PRETTIERDIR/prettier" ] || skip "prettier unavailable"
  export PATH="$PRETTIERDIR:$PATH"
  mkdir -p "$TDIR/jsconf"
  # A .js config is a code-exec vector in the (unsandboxed) hook; the hook must
  # neither load it nor fall back to defaults — it must skip entirely.
  printf '%s\n' 'module.exports = { singleQuote: true, semi: false }' > "$TDIR/jsconf/prettier.config.js"
  local f="$TDIR/jsconf/f.ts"
  printf 'const   x   =   "a"\n' > "$f"
  run run_hook format-on-save "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\"}}"
  [ "$status" -eq 0 ]
  run cat "$f"
  [[ "$output" == 'const   x   =   "a"' ]]
}

@test "format-on-save: honors .prettierignore" {
  [ -x "$PRETTIERDIR/prettier" ] || skip "prettier unavailable"
  export PATH="$PRETTIERDIR:$PATH"
  mkdir -p "$TDIR/ign/src"
  printf '%s\n' '{ "singleQuote": true, "semi": false }' > "$TDIR/ign/.prettierrc.json"
  printf '%s\n' 'src/f.ts' > "$TDIR/ign/.prettierignore"
  local f="$TDIR/ign/src/f.ts"
  printf 'const x = "a";\n' > "$f"
  run run_hook format-on-save "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\"}}"
  [ "$status" -eq 0 ]
  run cat "$f"
  # Ignored: original double-quote/semi content is preserved despite the config.
  [[ "$output" == 'const x = "a";' ]]
}
