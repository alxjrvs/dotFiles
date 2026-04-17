#!/usr/bin/env bash
# Multi-event notification dispatcher.
# Wired to Stop / Notification / SubagentStop; routes to desktop notifications
# (terminal-notifier or osascript) with per-event sound and optional voice.
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
sound="default"
speak=""

case "$event" in
  stop)
    # Gate: skip if the turn was short (user is likely watching).
    # UserPromptSubmit writes /tmp/claude-turn-start-<session> at turn start.
    ts_file="/tmp/claude-turn-start-${session_id:-default}"
    min_elapsed_s=30
    if [[ -f "$ts_file" ]]; then
      start_ts=$(cat "$ts_file" 2>/dev/null || echo 0)
      elapsed=$(( $(date +%s) - start_ts ))
      (( elapsed < min_elapsed_s )) && exit 0
    else
      exit 0
    fi
    body="turn complete"
    sound="Glass"
    ;;
  notification)
    case "$notif_type" in
      permission_prompt)
        body="${notif_msg:-permission requested}"
        sound="Ping"
        speak="Claude needs permission in $project"
        ;;
      idle_prompt)
        body="${notif_msg:-waiting for input}"
        sound="Funk"
        speak="Claude is waiting in $project"
        ;;
      *)
        body="${notif_msg:-${notif_title:-needs attention}}"
        sound="Ping"
        ;;
    esac
    ;;
  subagent-stop)
    if [[ -n "$agent_type" ]]; then
      body="${agent_type} finished"
    else
      body="subagent finished"
    fi
    if [[ -n "$last_msg" ]]; then
      snippet="${last_msg:0:80}"
      body="${body}: ${snippet}"
    fi
    sound="Pop"
    ;;
  *)
    exit 0
    ;;
esac

if command -v terminal-notifier &>/dev/null; then
  terminal-notifier \
    -title "$title" \
    -message "$body" \
    -sound "$sound" \
    -group "claude-$project" \
    >/dev/null 2>&1 &
  disown 2>/dev/null || true
elif command -v osascript &>/dev/null; then
  esc_body="${body//\"/\\\"}"
  esc_title="${title//\"/\\\"}"
  osascript -e "display notification \"$esc_body\" with title \"$esc_title\" sound name \"$sound\"" \
    >/dev/null 2>&1 &
  disown 2>/dev/null || true
fi

if [[ -n "$speak" ]] && command -v say &>/dev/null; then
  say "$speak" >/dev/null 2>&1 &
  disown 2>/dev/null || true
fi

exit 0
