[ -f /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"

# XDG
export XDG_CONFIG_HOME="$HOME/.config"

# PATH (login shell only — prevents duplication in subshells)
export PATH="$HOME/.local/bin:$PATH"

# GitHub auth stays out of the shell env — never exported. A standing
# GITHUB_PERSONAL_ACCESS_TOKEN would sit in the env of every subprocess Claude
# Code spawns (a low-friction exfiltration target). Anything that needs a token
# resolves it on demand: `gh auth token` (gh keychain) for git/CLI use, or the
# github MCP server via its headersHelper (op-agent header, which runs
# `op read` at connect time). Signing and SSH auth both go through the single
# 1Password agent (gpg.format = ssh + op-ssh-sign; ssh/config IdentityAgent) —
# no SSH_AUTH_SOCK export and no second agent here.
