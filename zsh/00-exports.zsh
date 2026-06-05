# Editor / pager / locale
export EDITOR="hx"
export VISUAL="$EDITOR"
export MANPAGER="less -R"
export LANG=en_US.UTF-8
export LESS='-RFX'
export RIPGREP_CONFIG_PATH="$HOME/.ripgreprc"

# GITHUB_PERSONAL_ACCESS_TOKEN is resolved once per login shell in .zprofile
# (from the gh CLI keychain) so it forks `gh auth token` only on login rather
# than on every interactive subshell, while still inheriting at fork time into
# child processes (e.g. the github MCP server). See CLAUDE.md secrets pattern 3.

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
