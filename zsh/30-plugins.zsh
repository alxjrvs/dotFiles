# Startup baseline (re-measured 2026-08-18, Apple Silicon): `zsh -i -c exit` ≈ 250 ms
# (0.29/0.24/0.24 s, first run cold). Per-eval breakdown: sheldon 52, atuin 40,
# mise 36, starship 32, fzf 4, zoxide 2 (ms). Was ≈ 199 ms on 2026-06-13; the
# drift is tool growth, not a regression here. Caching the six evals to files
# measured 188.6 → 88.5 ms of eval time (~250 → ~150 startup) and was rejected:
# it buys ~100 ms paid only on new tabs, in exchange for a cache dir plus
# version-keyed invalidation, and Ghostty's quick terminal keeps its surface
# alive so the cost is rarely paid at all. No single call is pathological; the only
# ways to cut the two largest are dropping plugins (sheldon) or deferring atuin
# init (loses instant Ctrl-R history) — both are UX tradeoffs, so the baseline
# is accepted as-is. Re-measure with: zsh -i -c exit under `time`.

# Homebrew completions

# Sheldon plugins (adds zsh-completions to fpath, loads FSH last)
eval "$(sheldon source)"

# Atuin shell history init lives in zsh/60-tools.zsh, after fzf's — both bind
# Ctrl-R and fzf's must not win (see the comment there).

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
