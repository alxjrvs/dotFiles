# Editor / pager / locale
export EDITOR="nvim"
export VISUAL="$EDITOR"
export LANG=en_US.UTF-8
export LESS='-RFX'
export RIPGREP_CONFIG_PATH="$HOME/.ripgreprc"

# Preferred terminal emulator. macOS has no system "default terminal" role,
# so this is the XDG-convention declaration of intent (not TERM_PROGRAM,
# which terminals set themselves). Ghostty is the daily driver; cmux stays
# installed for parallel agent sessions (boom code cmux).
export TERMINAL=ghostty

# GitHub tokens are never exported into the shell env; anything that needs one
# resolves it on demand via `gh auth token` (the github MCP server reads its PAT
# from 1Password through op-agent). See .zprofile for the rationale.

# maestro (mobile UI testing) CLI on PATH. Harmless on machines without it —
# a non-existent dir on PATH is a no-op.
export PATH="$PATH:$HOME/.maestro/bin"

# sharp (transitive dep of many JS projects via image tooling / miniflare)
# detects a global libvips via pkg-config and Homebrew's `vips` cask is
# installed on this machine — sharp then tries to build its native addon
# against that global libvips instead of using its own bundled prebuilt
# binary, and that from-source build fails on a missing node-addon-api.
# This forces sharp to always use its bundled prebuilt binary. Sharp reads
# this as a real env var (not an npm config key), so it must live here, not
# in ~/.npmrc.
export SHARP_IGNORE_GLOBAL_LIBVIPS=1

# Colored man pages (CMYK)
export LESS_TERMCAP_mb=$'\e[1;35m'
export LESS_TERMCAP_md=$'\e[1;36m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_so=$'\e[1;33;46m'
export LESS_TERMCAP_ue=$'\e[0m'
export LESS_TERMCAP_us=$'\e[1;35m'
