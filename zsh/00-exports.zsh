# Editor / pager / locale
export EDITOR="nvim"
export VISUAL="$EDITOR"
export LANG=en_US.UTF-8
export LESS='-RFX'
export RIPGREP_CONFIG_PATH="$HOME/.ripgreprc"
# No GITLEAKS_CONFIG export: that variable outranks a repo's own .gitleaks.toml, so a
# shell-wide export would silently drop every other repo's allowlists. The git template
# hook resolves ~/.config/gitleaks/gitleaks.toml itself, for repos that declare none.

# GitHub tokens are never exported into the shell env; anything that needs one
# resolves it on demand via `gh auth token`. See .zprofile for the rationale.

# sharp builds its native addon against a global libvips when pkg-config finds
# one, and that build fails on a missing node-addon-api. `vips` is present here
# as another formula's undeclared dependency. This forces the bundled prebuilt.
# A real env var, not an npm config key — so it belongs here, not in ~/.npmrc.
export SHARP_IGNORE_GLOBAL_LIBVIPS=1

# Colored man pages (CMYK)
export LESS_TERMCAP_mb=$'\e[1;35m'
export LESS_TERMCAP_md=$'\e[1;36m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_so=$'\e[1;33;46m'
export LESS_TERMCAP_ue=$'\e[0m'
export LESS_TERMCAP_us=$'\e[1;35m'
