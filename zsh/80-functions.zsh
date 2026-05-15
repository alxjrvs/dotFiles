# Make a dir and cd into it
function mkcd() { mkdir -p "$1" && cd "$1" }

# cd to the repo root
function cdroot() { cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Not in git repo"; return 1; } }

# Sorted disk-usage summary
function sz() { du -sh "${@:-.}" | sort -hr }

# Quick Claude-Code fix without committing
claude-fix() { claude -p "Fix the following issue without committing: $*"; }

# Run a command with secrets injected by 1Password CLI.
# Usage: op-run npm publish
# Resolves op:// references at exec time; nothing sensitive in shell env.
op-run() {
  command -v op &>/dev/null || { echo "op (1Password CLI) not installed"; return 1; }
  op run --no-masking -- "$@"
}

# Re-run a command on edits to common source extensions. Respects .gitignore.
# Usage: dev bun test    |    dev cargo build    |    dev make
dev() {
  command -v watchexec &>/dev/null || { echo "watchexec not installed"; return 1; }
  watchexec --clear -e ts,tsx,js,jsx,go,py,rs,lua,sh,zsh -- "$@"
}

# pueue: persistent task queue. Short aliases for the common verbs.
alias pq='pueue'
alias pqs='pueue status'
alias pqa='pueue add'
alias pql='pueue log'
alias pqf='pueue follow'
