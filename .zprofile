[ -f /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"

# XDG
export XDG_CONFIG_HOME="$HOME/.config"

# PATH (login shell only — prevents duplication in subshells)
export PATH="$HOME/.local/bin:$PATH"

# GitHub auth stays out of the shell env — never exported. A standing
# GITHUB_PERSONAL_ACCESS_TOKEN would sit in the env of every subprocess Claude
# Code spawns (a low-friction exfiltration target). Anything that needs a token
# resolves it on demand: `gh auth token` (gh keychain) for git/CLI use, and
# `op-agent git-credential` (1Password) for the agent's own pushes. Signing and
# SSH auth both go through the single
# 1Password agent (gpg.format = ssh + op-ssh-sign; ssh/config IdentityAgent) —
# no SSH_AUTH_SOCK export and no second agent here.

# Re-prepend the mise shims, LAST, because everything above this line demotes them.
#
# `.zshenv` already prepends them — but macOS `/etc/zprofile` runs `path_helper`, which does not
# prepend: it REBUILDS PATH from scratch (/etc/paths + /etc/paths.d/* first, whatever was already
# there appended after). Anything `.zshenv` set is pushed below the system set, and the
# `brew shellenv` at the top of this file compounds it by invoking path_helper again under
# PATH_HELPER_ROOT. Measured before this line: the shims sat at position 15, below /usr/bin.
#
# The consequence was version skew by shell context. `mise.toml` pins node = "25", and:
#     zsh -i  → mise install   v25.9.0   (interactive re-fixes it via `mise activate`)
#     zsh -l  → /opt/homebrew  v26.3.0   ← git hooks, launchd timers, editor + agent subprocesses
#     zsh -c  → mise shims     v25.9.0
# Every unattended context ran a different major version of node than the terminal did — and
# silently, because the terminal was the correct one.
#
# This has to be re-prepended HERE rather than reordered above: path_helper has already run by
# then, in /etc/zprofile, and re-sorts regardless of the order of these lines. `typeset -U path`
# in .zshenv collapses the resulting duplicate — it dedups but never reorders, which is why it
# could not prevent this on its own.
path=("$HOME/.local/share/mise/shims" $path)
