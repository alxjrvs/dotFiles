#!/usr/bin/env bash
# subagent-statusline — Claude Code subagent status line.
#
# Reads CC subagent JSON on stdin, emits {"tasks":[...]} on stdout for the
# Claude Code agent panel. A single jq pass does the whole transform — no
# per-task subshell/awk/date forks.
#
# Configured via ~/.claude/settings.json:
#   "subagentStatusLine": { "type": "command", "command": ".../subagent-statusline.sh" }
#
# Status -> state:  complete/completed/succeeded/success -> success;
#   failed/error -> error;  inactive/idle -> inactive;  else (running) -> success.
# Elapsed (compact = .columns < 100):  compact 30s/2m/1h ; normal 30s/2m05s/1h02m.
# Token:  plain integer abbreviation — 42 / 12k / 1M  (no decimals, no float math).
#
# Malformed/non-object input or a missing jq degrades to an empty panel.

set -euo pipefail

command -v jq > /dev/null 2>&1 || {
  printf '{"tasks":[]}\n'
  exit 0
}

input=$(cat)
printf '%s' "$input" | jq -e 'type == "object"' > /dev/null 2>&1 || {
  printf '{"tasks":[]}\n'
  exit 0
}

# Keys are emitted sorted (-S) for deterministic, diffable output.
printf '%s' "$input" | jq -cS '
  def pad2: tostring | if length < 2 then "0" + . else . end;
  def state:
    { "complete": "success", "completed": "success", "succeeded": "success", "success": "success",
      "failed": "error", "error": "error", "inactive": "inactive", "idle": "inactive" }[.] // "success";
  def elapsed($secs; $compact):
    if $compact then
      if   $secs < 60   then "\($secs)s"
      elif $secs < 3600 then "\($secs / 60 | floor)m"
      else                   "\($secs / 3600 | floor)h" end
    else
      if   $secs < 60   then "\($secs)s"
      elif $secs < 3600 then "\($secs / 60 | floor)m\((($secs % 60) | floor) | pad2)s"
      else                   "\($secs / 3600 | floor)h\(((($secs % 3600) / 60) | floor) | pad2)m" end
    end;
  def token($n):
    if   $n < 1000    then "\($n)"
    elif $n < 1000000 then "\($n / 1000 | floor)k"
    else                   "\($n / 1000000 | floor)M" end;
  (now * 1000) as $now
  | ((.columns // 200) | (tonumber? // 200) < 100) as $compact
  | { tasks: [
      ((.tasks // []) | if type == "array" then . else [] end)[]
      | (.tokenCount // 0 | if type == "number" then . else 0 end) as $tc
      | (.startTime // 0 | if type == "number" then . else 0 end) as $st
      | ((((($now - $st) / 1000) | floor)) | if . < 0 then 0 else . end) as $secs
      | {
          id: (.id // ""),
          state: ((.status // "running") | state),
          tokenText: token($tc),
          queuedText: "",
          queuedCount: 0,
          elapsed: elapsed($secs; $compact),
          tokenSamples: (.tokenSamples // [])
        }
    ] }
'
