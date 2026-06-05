[ -f /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"

# XDG
export XDG_CONFIG_HOME="$HOME/.config"

# PATH (login shell only — prevents duplication in subshells)
export PATH="$HOME/.local/bin:$PATH"

# GitHub token from the gh CLI keychain (CLAUDE.md secrets pattern 3).
# Login shell only: forks `gh auth token` once per login instead of on every
# interactive subshell, and still inherits at fork time into child processes
# (e.g. the github MCP server). The :- guard avoids re-forking when already set.
export GITHUB_PERSONAL_ACCESS_TOKEN="${GITHUB_PERSONAL_ACCESS_TOKEN:-$(gh auth token 2> /dev/null)}"

# Git signing -> dedicated ssh-agent at a FIXED socket path (silent signing,
# no per-commit prompts). Fixed path because the Claude sandbox compiles
# allowUnixSockets to literal seatbelt subpath rules -- Apple's launchd agent
# socket is per-boot random and can never be allowed. git signs via the
# agent (-U) and never reads the key file (sandbox denies ~/.ssh/id_*).
# Auth keys still live in 1Password (ssh/config IdentityAgent ignores
# SSH_AUTH_SOCK). dot sync (install/45-ssh.sh) provisions key + agent.
export SSH_AUTH_SOCK="$HOME/.ssh/agent/signing.sock"
ssh-add -l > /dev/null 2>&1 || {
  rm -f "$SSH_AUTH_SOCK"
  (umask 077 && ssh-agent -a "$SSH_AUTH_SOCK" > /dev/null 2>&1)
  ssh-add -q ~/.ssh/id_ed25519 2> /dev/null
}
