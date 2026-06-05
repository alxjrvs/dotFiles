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

# Git signing key → Apple ssh-agent (silent signing, no per-commit prompts).
# .gitconfig user.signingkey is the literal pubkey, so git signs via the
# agent (-U) and never reads the private key file — the Claude sandbox only
# allows the agent socket, not the key. Auth keys still live in 1Password
# (ssh/config IdentityAgent); this on-disk key exists for signing only.
# Login shell only; skips the fork when the agent already has identities.
ssh-add -l > /dev/null 2>&1 || ssh-add -q ~/.ssh/id_ed25519 2> /dev/null
