#!/usr/bin/env bash
# PostToolUse hook: trim oversized Bash stdout to save context tokens.
# Only intervenes when stdout exceeds threshold; stderr is preserved verbatim.
# User still sees the full output in the UI — this only changes what Claude sees.

set -uo pipefail

input=$(cat)

tool_name=$(printf '%s' "$input" | jq -r '.tool_name // empty')
[[ "$tool_name" != "Bash" ]] && exit 0

stdout=$(printf '%s' "$input" | jq -r '.tool_response.stdout // ""')
size=${#stdout}

threshold=20000
[[ $size -le $threshold ]] && exit 0

stderr=$(printf '%s' "$input" | jq -r '.tool_response.stderr // ""')
interrupted=$(printf '%s' "$input" | jq -r '(.tool_response.interrupted // false) | tostring')
is_image=$(printf '%s' "$input" | jq -r '(.tool_response.isImage // false) | tostring')

head_lines=200
tail_lines=100
total_lines=$(printf '%s\n' "$stdout" | wc -l | tr -d ' ')

if [[ $total_lines -gt $((head_lines + tail_lines)) ]]; then
  head_part=$(printf '%s' "$stdout" | head -n "$head_lines")
  tail_part=$(printf '%s' "$stdout" | tail -n "$tail_lines")
  elided_lines=$((total_lines - head_lines - tail_lines))
  trimmed=$(printf '%s\n... [trim-bash-output: elided %d lines / ~%dKB to save context — full output visible to user] ...\n%s' \
    "$head_part" "$elided_lines" "$((size / 1024))" "$tail_part")
else
  head_chars=8000
  tail_chars=4000
  head_part=${stdout:0:$head_chars}
  tail_part=${stdout: -$tail_chars}
  elided_chars=$((size - head_chars - tail_chars))
  trimmed=$(printf '%s\n... [trim-bash-output: elided %d chars (single huge line) — full output visible to user] ...\n%s' \
    "$head_part" "$elided_chars" "$tail_part")
fi

jq -n \
  --arg stdout "$trimmed" \
  --arg stderr "$stderr" \
  --argjson interrupted "$interrupted" \
  --argjson isImage "$is_image" \
  '{
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      updatedToolOutput: {
        stdout: $stdout,
        stderr: $stderr,
        interrupted: $interrupted,
        isImage: $isImage
      }
    }
  }'

exit 0
