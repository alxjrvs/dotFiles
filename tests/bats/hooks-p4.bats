#!/usr/bin/env bats
# Unit tests for the session-lifecycle + permission hooks added 2026-06:
# session-start, session-end (per-session shard bookends), config-change
# (anti-tamper ledger), and permission-request (read-only gh api auto-allow).
# HOME is pointed at a temp dir so ledger/shard writes never touch the real
# ~/.claude/state.

ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
JQDIR="$(dirname "$(mise which jq 2> /dev/null || command -v jq)")"

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

# ── session-start ───────────────────────────────────────────────────────────
@test "session-start: appends an event-tagged record to the per-session shard, silently" {
  run run_hook session-start '{"session_id":"sess-a","source":"startup","model":"claude-opus-4-8","cwd":"/repo","transcript_path":"/t/a.jsonl"}'
  [ "$status" -eq 0 ]
  # SessionStart stdout is injected into Claude's context — must be empty.
  [ -z "$output" ]
  local shard="$HOME/.claude/state/sessions/sess-a.jsonl"
  [ -f "$shard" ]
  run cat "$shard"
  [[ "$output" == *'"event":"session-start"'* ]]
  [[ "$output" == *'"source":"startup"'* ]]
  [[ "$output" == *'"model":"claude-opus-4-8"'* ]]
}

@test "session-start: never blocks (exits 0 silently on empty payload)" {
  run run_hook session-start '{}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -f "$HOME/.claude/state/sessions/unknown.jsonl" ]
}

# ── session-end ─────────────────────────────────────────────────────────────
@test "session-end: appends an event-tagged record with the end reason" {
  run run_hook session-end '{"session_id":"sess-b","reason":"logout","cwd":"/repo"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  local shard="$HOME/.claude/state/sessions/sess-b.jsonl"
  [ -f "$shard" ]
  run cat "$shard"
  [[ "$output" == *'"event":"session-end"'* ]]
  [[ "$output" == *'"reason":"logout"'* ]]
}

@test "session lifecycle: start and end land in the SAME shard as stop" {
  run run_hook session-start '{"session_id":"sess-c","source":"startup"}'
  [ "$status" -eq 0 ]
  run run_hook stop '{"session_id":"sess-c","cwd":"/repo"}'
  [ "$status" -eq 0 ]
  run run_hook session-end '{"session_id":"sess-c","reason":"other"}'
  [ "$status" -eq 0 ]
  local shard="$HOME/.claude/state/sessions/sess-c.jsonl"
  [ "$(wc -l < "$shard" | tr -d ' ')" -eq 3 ]
  run head -1 "$shard"
  [[ "$output" == *'"event":"session-start"'* ]]
  run tail -1 "$shard"
  [[ "$output" == *'"event":"session-end"'* ]]
}

# ── config-change ───────────────────────────────────────────────────────────
@test "config-change: appends to the flat ledger and never blocks" {
  local ledger="$HOME/.claude/state/config-changes.jsonl"
  run run_hook config-change '{"session_id":"sess-d","config_source":"user_settings","cwd":"/repo"}'
  [ "$status" -eq 0 ]
  # Telemetry only: any stdout decision (e.g. {"decision":"block"}) would
  # reject the config change — must stay silent.
  [ -z "$output" ]
  [ -f "$ledger" ]
  [ "$(wc -l < "$ledger" | tr -d ' ')" -eq 1 ]
  run cat "$ledger"
  [[ "$output" == *'"config_source":"user_settings"'* ]]
}

@test "config-change: exits 0 and appends on partial payload" {
  run run_hook config-change '{}'
  [ "$status" -eq 0 ]
  run run_hook config-change '{"config_source":"skills"}'
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$HOME/.claude/state/config-changes.jsonl" | tr -d ' ')" -eq 2 ]
}

# ── permission-request: read-only gh api auto-allow ─────────────────────────
@test "permission-request: allows a plain gh api GET" {
  run run_hook permission-request '{"tool_name":"Bash","tool_input":{"command":"gh api repos/owner/repo/pulls"}}'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "PermissionRequest"'
  echo "$output" | jq -e '.hookSpecificOutput.decision.behavior == "allow"'
}

@test "permission-request: allows explicit -X GET and --method GET" {
  run run_hook permission-request '{"tool_name":"Bash","tool_input":{"command":"gh api -X GET repos/owner/repo"}}'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.decision.behavior == "allow"'
  run run_hook permission-request '{"tool_name":"Bash","tool_input":{"command":"gh api --method GET user"}}'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.decision.behavior == "allow"'
}

@test "permission-request: silent on non-GET methods (falls back to the dialog)" {
  local cmds=(
    'gh api -X POST repos/owner/repo/issues'
    'gh api -XDELETE repos/owner/repo'
    'gh api --method=PATCH repos/owner/repo'
  )
  for cmd in "${cmds[@]}"; do
    run run_hook permission-request "$(jq -cn --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}')"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
}

@test "permission-request: silent on body-mutating field flags (gh api -f flips to POST)" {
  local cmds=(
    'gh api repos/owner/repo/issues -f title=x'
    'gh api graphql -F query=@q.graphql'
    'gh api user --field name=x'
    'gh api user --raw-field bio=x'
    'gh api user --input payload.json'
  )
  for cmd in "${cmds[@]}"; do
    run run_hook permission-request "$(jq -cn --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}')"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
}

@test "permission-request: silent on shell metacharacters (no chaining/substitution sneaks through)" {
  local cmds=(
    'gh api user | jq .login'
    'gh api user; rm -rf /'
    'gh api user && echo ok'
    'gh api repos/$(whoami)/x'
    'gh api user > /tmp/out'
  )
  for cmd in "${cmds[@]}"; do
    run run_hook permission-request "$(jq -cn --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}')"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
}

@test "permission-request: silent on non-gh-api commands and non-Bash tools" {
  run run_hook permission-request '{"tool_name":"Bash","tool_input":{"command":"git status"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run run_hook permission-request '{"tool_name":"Edit","tool_input":{"file_path":"/x"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
