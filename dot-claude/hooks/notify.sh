#!/usr/bin/env bash
# Multi-event notification dispatcher.
# Wired to Stop / Notification / SubagentStop; routes to silent desktop
# notifications (terminal-notifier or osascript).
# Argument: event type ("stop" | "notification" | "subagent-stop").
# Exit 0 always — best-effort, never blocks.

set -uo pipefail

event="${1:-unknown}"
input=$(cat 2>/dev/null || true)

session_id=$(echo "$input" | jq -r '.session_id // empty' 2>/dev/null)
cwd=$(echo "$input" | jq -r '.cwd // empty' 2>/dev/null)
notif_type=$(echo "$input" | jq -r '.notification_type // empty' 2>/dev/null)
notif_title=$(echo "$input" | jq -r '.title // empty' 2>/dev/null)
notif_msg=$(echo "$input" | jq -r '.message // empty' 2>/dev/null)
agent_type=$(echo "$input" | jq -r '.agent_type // empty' 2>/dev/null)
last_msg=$(echo "$input" | jq -r '.last_assistant_message // empty' 2>/dev/null)

if [[ -n "$cwd" ]]; then
  project=$(basename "$cwd")
else
  project="claude"
fi

title="claude: $project"
body=""

# Shared duration gate: skip notification if the turn was short.
# UserPromptSubmit writes /tmp/claude-turn-start-<session> at turn start.
gate_short_turn() {
  local ts_file="/tmp/claude-turn-start-${session_id:-default}"
  local min_elapsed_s=30
  if [[ -f "$ts_file" ]]; then
    local start_ts elapsed
    start_ts=$(cat "$ts_file" 2>/dev/null || echo 0)
    elapsed=$(( $(date +%s) - start_ts ))
    (( elapsed < min_elapsed_s )) && exit 0
  else
    exit 0
  fi
}

case "$event" in
  stop)
    gate_short_turn
    body="turn complete"
    ;;
  notification)
    case "$notif_type" in
      permission_prompt)
        body="${notif_msg:-permission requested}"
        ;;
      idle_prompt)
        body="${notif_msg:-waiting for input}"
        ;;
      *)
        body="${notif_msg:-${notif_title:-needs attention}}"
        ;;
    esac
    ;;
  subagent-stop)
    gate_short_turn
    if [[ -n "$agent_type" ]]; then
      body="${agent_type} finished"
    else
      body="subagent finished"
    fi
    if [[ -n "$last_msg" ]]; then
      snippet="${last_msg:0:80}"
      body="${body}: ${snippet}"
    fi
    ;;
  *)
    exit 0
    ;;
esac

if command -v terminal-notifier &>/dev/null; then
  terminal-notifier \
    -title "$title" \
    -message "$body" \
    -group "claude-$project" \
    >/dev/null 2>&1 &
  disown 2>/dev/null || true
elif command -v osascript &>/dev/null; then
  esc_body="${body//\"/\\\"}"
  esc_title="${title//\"/\\\"}"
  osascript -e "display notification \"$esc_body\" with title \"$esc_title\"" \
    >/dev/null 2>&1 &
  disown 2>/dev/null || true
fi

exit 0
