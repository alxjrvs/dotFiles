# Startup baseline (measured 2026-06-13, Apple Silicon): `zsh -i -c exit` ≈ 199 ms
# avg over 10 runs. Per-eval breakdown: sheldon 59, atuin 47, starship 29,
# mise 29, fzf 22, compinit 11 (ms). No single call is pathological; the only
# ways to cut the two largest are dropping plugins (sheldon) or deferring atuin
# init (loses instant Ctrl-R history) — both are UX tradeoffs, so the baseline
# is accepted as-is. Re-measure with: zsh -i -c exit under `time`.

# Homebrew completions
fpath+=(/opt/homebrew/share/zsh/site-functions)

# Sheldon plugins (adds zsh-completions to fpath, loads FSH last)
eval "$(sheldon source)"

# Atuin shell history — Ctrl-R fuzzy search. --disable-up-arrow keeps Up/Down as
# plain zsh history navigation instead of opening atuin's search on every Up.
eval "$(atuin init zsh --disable-up-arrow)"

# Syntax highlighting theme (Jack Kirby CMYK) - F-Sy-H overrides
typeset -A FAST_HIGHLIGHT_STYLES
FAST_HIGHLIGHT_STYLES[default]='fg=#e6edf3'
FAST_HIGHLIGHT_STYLES[command]='fg=#4db8cc'
FAST_HIGHLIGHT_STYLES[alias]='fg=#4db8cc'
FAST_HIGHLIGHT_STYLES[function]='fg=#d06cb8'
FAST_HIGHLIGHT_STYLES[builtin]='fg=#4db8cc'
FAST_HIGHLIGHT_STYLES[reserved-word]='fg=#d06cb8'
FAST_HIGHLIGHT_STYLES[unknown-token]='fg=#e05050'
FAST_HIGHLIGHT_STYLES[precommand]='fg=#d06cb8,underline'
FAST_HIGHLIGHT_STYLES[single-quoted-argument]='fg=#d4b84a'
FAST_HIGHLIGHT_STYLES[double-quoted-argument]='fg=#d4b84a'
FAST_HIGHLIGHT_STYLES[dollar-quoted-argument]='fg=#d4b84a'
FAST_HIGHLIGHT_STYLES[dollar-double-quoted-argument]='fg=#d48040'
FAST_HIGHLIGHT_STYLES[back-quoted-argument]='fg=#d48040'
FAST_HIGHLIGHT_STYLES[single-hyphen-option]='fg=#8b949e'
FAST_HIGHLIGHT_STYLES[double-hyphen-option]='fg=#8b949e'
FAST_HIGHLIGHT_STYLES[globbing]='fg=#d48040'
FAST_HIGHLIGHT_STYLES[redirection]='fg=#4db8cc'
FAST_HIGHLIGHT_STYLES[commandseparator]='fg=#4db8cc'
FAST_HIGHLIGHT_STYLES[assign]='fg=#d4b84a'
FAST_HIGHLIGHT_STYLES[comment]='fg=#8b949e,italic'
FAST_HIGHLIGHT_STYLES[path]='fg=#e6edf3,underline'
