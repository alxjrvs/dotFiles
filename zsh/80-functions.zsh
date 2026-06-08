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
# Masking is left ON (no --no-masking): the child process still receives the
# real resolved value, but 1Password redacts it from the child's stdout/stderr,
# so secrets don't land in command output an agent/transcript could capture.
# If a tool genuinely breaks under masked output, add a one-off wrapper and
# document why, rather than weakening this sanctioned default.
op-run() {
  command -v op &>/dev/null || { echo "op (1Password CLI) not installed"; return 1; }
  op run -- "$@"
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

# Start pueued on first interactive shell if it isn't already running.
# The aliases above all silently fail with "no connection to daemon"
# otherwise — this used to require manual `pueued -d`. Detached, so
# shell startup pays at most ~50ms on the cold-start path and zero
# when the daemon is up.
if [[ -o interactive ]] && command -v pueued &>/dev/null; then
  pueue status &>/dev/null || pueued -d &>/dev/null &!
fi
