[ -f /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"

# XDG
export XDG_CONFIG_HOME="$HOME/.config"

# PATH (login shell only — prevents duplication in subshells)
export PATH="$HOME/.local/bin:$PATH"
