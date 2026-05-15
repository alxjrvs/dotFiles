# Make a dir and cd into it
function mkcd() { mkdir -p "$1" && cd "$1" }

# cd to the repo root
function cdroot() { cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Not in git repo"; return 1; } }

# Sorted disk-usage summary
function sz() { du -sh "${@:-.}" | sort -hr }

# Quick Claude-Code fix without committing
claude-fix() { claude -p "Fix the following issue without committing: $*"; }
