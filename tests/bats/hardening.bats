#!/usr/bin/env bats
# Unit tests for the claude-setup-hardening pass.
# Covers: lock-file-guard fail-closed (jq absent), mcp-guard destructive deny,
# and the format-on-save eslint-removal guard.

ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
JQDIR="$(dirname "$(mise which jq 2> /dev/null || command -v jq)")"

setup() {
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

# jq pretty-prints deny payloads with a space: "permissionDecision": "deny"
# The jq-absent fail-closed path uses a compact printf, so match both forms.
is_deny() { [[ "$1" == *'"permissionDecision": "deny"'* || "$1" == *'"permissionDecision":"deny"'* ]]; }

# jq_absent: run a hook with a PATH that has bash (/bin) but no jq, so the
# guard's `command -v jq` lookup fails. The shebang uses an absolute /usr/bin/env
# so it resolves regardless of PATH. Used to prove the fail-closed deny path.
jq_absent() {
  local hook="$1" json="$2"
  printf '%s' "$json" | PATH=/bin "$ROOT/hooks/$hook"
}

# ── lock-file-guard: fail-closed when jq is absent ──────────────────────────
# With jq off PATH the guard cannot inspect the payload, so it must DENY rather
# than silently allow the edit.
@test "lock-file-guard: fails closed (deny) when jq is unavailable" {
  run jq_absent lock-file-guard '{"tool_input":{"file_path":"/x/bun.lock"}}'
  [ "$status" -eq 0 ]
  is_deny "$output"
  [[ "$output" == *"jq unavailable"* ]]
}

# Sanity: even a non-lock path fails closed when jq is gone (cannot inspect).
@test "lock-file-guard: jq absent denies regardless of path" {
  run jq_absent lock-file-guard '{"tool_input":{"file_path":"/x/main.rs"}}'
  [ "$status" -eq 0 ]
  is_deny "$output"
}

# ── lock-file-guard: known lock denied, normal file silent ──────────────────
@test "lock-file-guard: denies Cargo.lock" {
  run run_hook lock-file-guard '{"tool_input":{"file_path":"/repo/Cargo.lock"}}'
  [ "$status" -eq 0 ]
  is_deny "$output"
}

@test "lock-file-guard: silent on a normal source file" {
  run run_hook lock-file-guard '{"tool_input":{"file_path":"/repo/src/lib.rs"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── mcp-guard ───────────────────────────────────────────────────────────────
@test "mcp-guard: allows merge_pull_request (PR merges are permitted)" {
  run run_hook mcp-guard '{"tool_name":"mcp__github__merge_pull_request","tool_input":{}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "mcp-guard: denies delete_file and push_files" {
  run run_hook mcp-guard '{"tool_name":"mcp__github__delete_file","tool_input":{}}'
  [ "$status" -eq 0 ]
  is_deny "$output"
  run run_hook mcp-guard '{"tool_name":"mcp__github__push_files","tool_input":{}}'
  [ "$status" -eq 0 ]
  is_deny "$output"
}

@test "mcp-guard: silent on a read MCP tool (get_file_contents)" {
  run run_hook mcp-guard '{"tool_name":"mcp__github__get_file_contents","tool_input":{}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "mcp-guard: non-MCP tool is ignored" {
  run run_hook mcp-guard '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "mcp-guard: fails closed (deny) when jq is unavailable" {
  run jq_absent mcp-guard '{"tool_name":"mcp__github__get_file_contents"}'
  [ "$status" -eq 0 ]
  is_deny "$output"
  [[ "$output" == *"jq unavailable"* ]]
}

# ── format-on-save: eslint removal guard ────────────────────────────────────
# The eslint --fix arm was an unsandboxed code-exec vector and was removed.
# "eslint" may still appear in explanatory comments, but it must never be
# invoked: no non-comment line may reference it.
@test "format-on-save: eslint is not invoked (no non-comment reference)" {
  local hits
  # Strip comment lines (optional leading whitespace then '#') before grepping.
  hits=$(grep -vE '^[[:space:]]*#' "$ROOT/hooks/format-on-save" | grep -ci 'eslint' || true)
  [ "$hits" -eq 0 ]
}
