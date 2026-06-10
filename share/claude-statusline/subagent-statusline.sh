#!/usr/bin/env bash
# subagent-statusline — self-contained Claude Code subagent status line.
#
# Reads CC subagent JSON on stdin, maps each task to a status record, emits
# {"tasks":[...]} on stdout for the Claude Code agent panel.
#
# Configured via ~/.claude/settings.json:
#   "subagentStatusLine": { "type": "command", "command": "path/to/subagent-statusline.sh" }
#
# Input schema (empirically inferred from CC v2.1.150):
#   {
#     "session_id": "...",
#     "columns": 168,
#     "tasks": [
#       {
#         "id": "agent-xyz",
#         "status": "running"|"complete"|"failed"|...,
#         "startTime": <epoch ms>,
#         "tokenCount": 1234,
#         "tokenSamples": [<numbers>]
#       }, ...
#     ]
#   }
#
# Output schema:
#   {
#     "tasks": [
#       {
#         "id": "...",
#         "state": "success"|"error"|"inactive",
#         "tokenText": "42"|"1.0k"|"1.0M",
#         "queuedText": "",
#         "queuedCount": 0,
#         "elapsed": "30s"|"2m05s"|"1h02m",
#         "tokenSamples": [<numbers>]
#       }, ...
#     ]
#   }
#
# Status -> state mapping (from subagent_statusline.rs):
#   complete|completed|succeeded|success -> "success"
#   failed|error                         -> "error"
#   inactive|idle                        -> "inactive"
#   anything else (running, unknown)     -> "success"
#
# Elapsed format (compact = columns < 100):
#   compact:  30s / 2m / 1h    (single largest unit)
#   normal:   30s / 2m05s / 1h02m
#
# Token format (compact):
#   compact:  42 / 1k / 1M    (integer, no decimal)
#   normal:   42 / 1.0k / 1.0M
#
# Bash 3.2 compatible (macOS system bash).

set -euo pipefail

# ── Helpers ────────────────────────────────────────────────────────────────

# now_ms: current time in milliseconds since epoch.
# Uses gdate (coreutils) when available for %3N; falls back to date (seconds
# precision only) on macOS system date which lacks %3N.
now_ms() {
  if command -v gdate > /dev/null 2>&1; then
    gdate +%s%3N
  else
    # date on macOS does not support %3N; multiply seconds by 1000.
    printf '%s000' "$(date +%s)"
  fi
}

# format_elapsed <secs> <compact>
# compact=1 -> single largest unit: 30s / 2m / 1h
# compact=0 -> 30s / 2m05s / 1h02m
format_elapsed() {
  local secs=$1 compact=$2
  if [ "$compact" -eq 1 ]; then
    if [ "$secs" -lt 60 ]; then
      printf '%ss' "$secs"
    elif [ "$secs" -lt 3600 ]; then
      printf '%sm' "$((secs / 60))"
    else
      printf '%sh' "$((secs / 3600))"
    fi
  else
    if [ "$secs" -lt 60 ]; then
      printf '%ss' "$secs"
    elif [ "$secs" -lt 3600 ]; then
      local m=$((secs / 60))
      local s=$((secs % 60))
      printf '%sm%02ds' "$m" "$s"
    else
      local h=$((secs / 3600))
      local m=$(((secs % 3600) / 60))
      printf '%sh%02dm' "$h" "$m"
    fi
  fi
}

# format_token_count <n> <compact>
# compact=1 -> 42 / 1k / 1M  (integer, no decimal)
# compact=0 -> 42 / 1.0k / 1.0M
format_token_count() {
  local n=$1 compact=$2
  if [ "$compact" -eq 1 ]; then
    if [ "$n" -lt 1000 ]; then
      printf '%s' "$n"
    elif [ "$n" -lt 1000000 ]; then
      printf '%sk' "$((n / 1000))"
    else
      printf '%sM' "$((n / 1000000))"
    fi
  else
    if [ "$n" -lt 1000 ]; then
      printf '%s' "$n"
    elif [ "$n" -lt 1000000 ]; then
      # One decimal place: use awk for float formatting.
      awk -v n="$n" 'BEGIN{ printf "%.1fk", n / 1000.0 }'
    else
      awk -v n="$n" 'BEGIN{ printf "%.1fM", n / 1000000.0 }'
    fi
  fi
}

# map_status_to_state <status_str> -> prints state string
map_status_to_state() {
  local status=$1
  case "$status" in
    complete | completed | succeeded | success) printf 'success' ;;
    failed | error) printf 'error' ;;
    inactive | idle) printf 'inactive' ;;
    *) printf 'success' ;; # running / unknown -> success
  esac
}

# ── Main ────────────────────────────────────────────────────────────────────

if ! command -v jq > /dev/null 2>&1; then
  printf '{"tasks":[]}\n'
  exit 0
fi

input=$(cat)

# Validate up front: malformed/non-object input must degrade to an empty
# panel, not abort under set -e and blank it (same spirit as the jq-missing
# fallback above).
if ! printf '%s' "$input" | jq -e 'type == "object"' > /dev/null 2>&1; then
  printf '{"tasks":[]}\n'
  exit 0
fi

# Extract columns; compact when < 100.
cols=$(printf '%s' "$input" | jq -r '.columns // ""' 2> /dev/null || printf '')
compact=0
case "$cols" in
  '' | *[!0-9]*) compact=0 ;;
  *) [ "$cols" -lt 100 ] && compact=1 || compact=0 ;;
esac

now=$(now_ms)

# Extract task count to iterate by index (0 when .tasks is missing or not an
# array — never abort under set -e).
task_count=$(printf '%s' "$input" | jq '(.tasks // []) | if type == "array" then length else 0 end' 2> /dev/null || printf '0')
case "$task_count" in '' | *[!0-9]*) task_count=0 ;; esac

# Build tasks_out JSON array by iterating over each task.
tasks_out='[]'
i=0
while [ "$i" -lt "$task_count" ]; do
  # Extract fields for task $i in one jq pass, as name-keyed key=value lines
  # parsed by `case` (bash 3.2 safe) — a CC schema addition or reorder can't
  # silently shift fields; unknown keys are ignored.
  task_fields=$(printf '%s' "$input" | jq -r --argjson idx "$i" '
    .tasks[$idx] |
    "id=\(.id // "")",
    "status=\(.status // "running")",
    "token_count=\(.tokenCount // 0 | tostring)",
    "start_time=\(.startTime // 0 | tostring)",
    "token_samples=\(.tokenSamples // [] | tojson)"
  ' 2> /dev/null || printf '')

  task_id="" task_status="running" task_token_count=0 task_start_time=0
  task_token_samples='[]'
  while IFS= read -r _kv || [ -n "$_kv" ]; do
    case "$_kv" in *=*) ;; *) continue ;; esac
    _k=${_kv%%=*}
    _v=${_kv#*=}
    case "$_k" in
      id) task_id=$_v ;;
      status) task_status=$_v ;;
      token_count) task_token_count=$_v ;;
      start_time) task_start_time=$_v ;;
      token_samples) task_token_samples=$_v ;;
    esac
  done <<< "$task_fields"

  # Validate numeric fields; default to 0 on garbage.
  case "$task_token_count" in '' | *[!0-9]*) task_token_count=0 ;; esac
  case "$task_start_time" in '' | *[!0-9]*) task_start_time=$now ;; esac

  # Compute elapsed seconds: (now_ms - startTime_ms) / 1000, floored.
  # Use awk to handle large integer arithmetic safely.
  elapsed_secs=$(awk -v now="$now" -v st="$task_start_time" 'BEGIN{
    diff = now - st
    if (diff < 0) diff = 0
    printf "%d", int(diff / 1000)
  }')

  state=$(map_status_to_state "$task_status")
  elapsed_str=$(format_elapsed "$elapsed_secs" "$compact")
  token_text=$(format_token_count "$task_token_count" "$compact")

  # Append to tasks_out array using jq.
  tasks_out=$(printf '%s' "$tasks_out" | jq \
    --arg id "$task_id" \
    --arg state "$state" \
    --arg token_text "$token_text" \
    --arg elapsed "$elapsed_str" \
    --argjson token_samples "$task_token_samples" \
    '. += [{
      "id": $id,
      "state": $state,
      "tokenText": $token_text,
      "queuedText": "",
      "queuedCount": 0,
      "elapsed": $elapsed,
      "tokenSamples": $token_samples
    }]')

  i=$((i + 1))
done

# Emit final JSON object (compact, one line, keys sorted for deterministic output).
printf '%s' "$tasks_out" | jq -c -S '{tasks: .}'
