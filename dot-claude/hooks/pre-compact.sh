#!/usr/bin/env bash
# PreCompact hook: snapshot session state to ~/.claude/compaction-logs/
# so "what were we doing" can be recovered after context is compacted.
# Exit 0 always — informational; never blocks compaction.

set -uo pipefail

input=$(cat 2>/dev/null || true)
session_id=$(echo "$input" | jq -r '.session_id // "unknown"' 2>/dev/null)
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
trigger=$(echo "$input" | jq -r '.trigger // "auto"' 2>/dev/null)
cwd=$(echo "$input" | jq -r '.cwd // empty' 2>/dev/null)
custom=$(echo "$input" | jq -r '.custom_instructions // empty' 2>/dev/null)

log_dir="$HOME/.claude/compaction-logs"
mkdir -p "$log_dir" 2>/dev/null || exit 0
log_file="$log_dir/$(date +%Y%m%d-%H%M%S)-${session_id}.md"

git_branch=""
git_dirty=0
if [[ -n "$cwd" ]] && git -C "$cwd" rev-parse --is-inside-work-tree &>/dev/null; then
  git_branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || echo detached)
  git_dirty=$(git -C "$cwd" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
fi

{
  echo "# Compaction snapshot"
  echo ""
  echo "- **session**: \`$session_id\`"
  echo "- **trigger**: $trigger"
  echo "- **at**: $(date -Iseconds 2>/dev/null || date)"
  echo "- **cwd**: \`$cwd\`"
  [[ -n "$git_branch" ]] && echo "- **git**: \`$git_branch\` ($git_dirty modified)"
  [[ -n "$transcript_path" && -f "$transcript_path" ]] && echo "- **transcript**: \`$transcript_path\`"
  if [[ -n "$custom" ]]; then
    echo ""
    echo "## Custom compact instructions"
    echo ""
    echo "$custom"
  fi
  echo ""
  echo "> Recover context by reading the transcript path above, or rerun a summary prompt."
} > "$log_file" 2>/dev/null || true

find "$log_dir" -maxdepth 1 -name '*.md' -mtime +14 -delete 2>/dev/null || true

exit 0
