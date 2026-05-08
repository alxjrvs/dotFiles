#!/usr/bin/env bash
# PreCompact hook: log compaction events for visibility.
# Useful for tuning CLAUDE_AUTOCOMPACT_PCT_OVERRIDE — if you see frequent compactions
# at unexpected moments, the threshold may be too low.

set -uo pipefail

input=$(cat)
log_file="$HOME/.claude/compact-log.jsonl"

ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
session_id=$(printf '%s' "$input" | jq -r '.session_id // empty')
trigger=$(printf '%s' "$input" | jq -r '.trigger // .hookSpecificOutput.trigger // "unknown"')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')

jq -cn \
  --arg ts "$ts" \
  --arg session "$session_id" \
  --arg trigger "$trigger" \
  --arg cwd "$cwd" \
  '{ts: $ts, session: $session, trigger: $trigger, cwd: $cwd}' \
  >> "$log_file" 2>/dev/null || true

exit 0
