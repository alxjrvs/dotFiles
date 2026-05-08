#!/usr/bin/env bash
# PermissionDenied hook: log denials so you can spot commands that keep getting
# blocked and add them to permissions.allow proactively.
# Review periodically: `tail -50 ~/.claude/denial-log.jsonl | jq -c .`

set -uo pipefail

input=$(cat)
log_file="$HOME/.claude/denial-log.jsonl"

ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
session_id=$(printf '%s' "$input" | jq -r '.session_id // empty')
tool_name=$(printf '%s' "$input" | jq -r '.tool_name // empty')
# Truncate tool_input to keep log line size reasonable.
tool_input=$(printf '%s' "$input" | jq -c '.tool_input // {}' | cut -c1-500)
reason=$(printf '%s' "$input" | jq -r '.reason // .hookSpecificOutput.reason // empty')

jq -cn \
  --arg ts "$ts" \
  --arg session "$session_id" \
  --arg tool "$tool_name" \
  --arg input "$tool_input" \
  --arg reason "$reason" \
  '{ts: $ts, session: $session, tool: $tool, input: $input, reason: $reason}' \
  >> "$log_file" 2>/dev/null || true

exit 0
