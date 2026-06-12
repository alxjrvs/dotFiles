[ -f /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"

# XDG
export XDG_CONFIG_HOME="$HOME/.config"

# PATH (login shell only — prevents duplication in subshells)
export PATH="$HOME/.local/bin:$PATH"

# GitHub auth is intentionally NOT exported into the shell environment.
# Previously GITHUB_PERSONAL_ACCESS_TOKEN was exported here (from the gh
# keychain) so the github MCP server could inherit it at fork time. But that
# also placed the token in the env of every Bash subprocess Claude Code spawns
# (CLAUDE_CODE_SUBPROCESS_ENV_SCRUB only strips Anthropic/cloud creds, not a
# GitHub PAT, and its list is not user-extensible), making it a low-friction
# exfiltration target. Instead the github MCP server resolves the token on
# demand from the gh keychain: the stock github plugin (which hard-codes
# `Bearer ${GITHUB_PERSONAL_ACCESS_TOKEN}` and so can't, leaving it empty) is
# disabled, replaced by a user-scope `github` server whose `headersHelper`
# (gh/gh-mcp-auth-header -> ~/.local/bin) runs `gh auth token` at connect time.
# Anything else that genuinely needs the token should likewise resolve it on
# demand with `gh auth token` rather than inheriting a long-lived copy here.

# Git signing -> dedicated ssh-agent at a FIXED socket path (silent signing,
# no per-commit prompts; stable across reboots, unlike Apple's per-boot-random
# launchd agent socket). git signs via the agent (-U).
# Auth keys still live in 1Password (ssh/config IdentityAgent ignores
# SSH_AUTH_SOCK). dot sync (install/45-ssh.sh) provisions key + agent.
export SSH_AUTH_SOCK="$HOME/.ssh/agent/signing.sock"
ssh-add -l > /dev/null 2>&1 || {
  rm -f "$SSH_AUTH_SOCK"
  (umask 077 && ssh-agent -a "$SSH_AUTH_SOCK" > /dev/null 2>&1)
  ssh-add -q ~/.ssh/id_ed25519 2> /dev/null
}
