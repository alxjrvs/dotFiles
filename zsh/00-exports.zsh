# Editor / pager / locale
export EDITOR="nvim"
export VISUAL="$EDITOR"
export LANG=en_US.UTF-8
export LESS='-RFX'
export RIPGREP_CONFIG_PATH="$HOME/.ripgreprc"

# Preferred terminal emulator. macOS has no system "default terminal" role,
# so this is the XDG-convention declaration of intent (not TERM_PROGRAM,
# which terminals set themselves). Ghostty is the daily driver; cmux stays
# installed for parallel agent sessions (dot ws --app cmux).
export TERMINAL=ghostty

# GitHub tokens are never exported into the shell env; anything that needs one
# resolves it on demand via `gh auth token` (the github MCP server reads its PAT
# from 1Password through gh/gh-mcp-auth-header). See .zprofile for the rationale.

# Colored man pages (CMYK)
export LESS_TERMCAP_mb=$'\e[1;35m'
export LESS_TERMCAP_md=$'\e[1;36m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_so=$'\e[1;33;46m'
export LESS_TERMCAP_ue=$'\e[0m'
export LESS_TERMCAP_us=$'\e[1;35m'
