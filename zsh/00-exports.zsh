# Editor / pager / locale
export EDITOR="hx"
export VISUAL="$EDITOR"
# Preferred terminal for tools that honor $TERMINAL (cmux is the Ghostty-based
# default; Ghostty.app stays installed as the fallback emulator).
export TERMINAL="/Applications/cmux.app/Contents/Resources/bin/cmux"
export MANPAGER="less -R"
export LANG=en_US.UTF-8
export LESS='-RFX'
export RIPGREP_CONFIG_PATH="$HOME/.ripgreprc"

# GitHub MCP server (plugin:github:github) reads this; sourced lazily from gh CLI keychain.
export GITHUB_PERSONAL_ACCESS_TOKEN="${GITHUB_PERSONAL_ACCESS_TOKEN:-$(gh auth token 2>/dev/null)}"

# Colored man pages (CMYK)
export LESS_TERMCAP_mb=$'\e[1;35m'
export LESS_TERMCAP_md=$'\e[1;36m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_so=$'\e[1;33;46m'
export LESS_TERMCAP_ue=$'\e[0m'
export LESS_TERMCAP_us=$'\e[1;35m'

# Gnar `meta` plugin: opt in to adoption telemetry. The Stop hook
# (stop-skill-telemetry.sh) no-ops unless this is set; flipping it on
# here lets every Claude session ship one event per Stop to the
# gnar-telem Worker. See meta/README.md for the privacy contract.
export META_TELEMETRY_ENABLE=1
