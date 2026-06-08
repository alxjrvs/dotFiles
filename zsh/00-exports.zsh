# Editor / pager / locale
export EDITOR="nvim"
export VISUAL="$EDITOR"
export MANPAGER="less -R"
export LANG=en_US.UTF-8
export LESS='-RFX'
export RIPGREP_CONFIG_PATH="$HOME/.ripgreprc"

# GITHUB_PERSONAL_ACCESS_TOKEN is deliberately NOT exported (see .zprofile for
# the rationale): exporting it leaked the PAT into every Bash subprocess Claude
# Code spawns. The github MCP server authenticates via the gh keychain; resolve
# the token on demand with `gh auth token` when a tool needs it.

# Colored man pages (CMYK)
export LESS_TERMCAP_mb=$'\e[1;35m'
export LESS_TERMCAP_md=$'\e[1;36m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_so=$'\e[1;33;46m'
export LESS_TERMCAP_ue=$'\e[0m'
export LESS_TERMCAP_us=$'\e[1;35m'

# Opt in to adoption telemetry. Consumed by the Claude Code Stop hook
# (hooks/stop) — it no-ops unless this is set; flipping it on here lets a
# session emit one event per Stop. See hooks/stop for the behavior contract.
export META_TELEMETRY_ENABLE=1
