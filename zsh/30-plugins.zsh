# Homebrew completions
fpath+=(/opt/homebrew/share/zsh/site-functions)

autoload -Uz add-zsh-hook

# Cached-init helper. Caches the output of a tool's init command (e.g.
# `mise activate zsh`) and sources it, regenerating only when the tool
# binary is newer than the cache. Avoids subprocess spawn per shell.
_zsh_cached_load() {
  local name="$1" cmd="$2" bin="$3"
  local cache="${XDG_CACHE_HOME:-$HOME/.cache}/zsh-init/${name}.zsh"
  # -s also rejects zero-byte caches left behind by a failed init command —
  # otherwise an empty cache "newer than" the binary sticks forever.
  if [[ ! -s "$cache" || "$bin" -nt "$cache" ]]; then
    mkdir -p "${cache:h}"
    local tmp="${cache}.tmp.$$"
    if command ${=cmd} > "$tmp" 2>/dev/null && [[ -s "$tmp" ]]; then
      mv "$tmp" "$cache"
    else
      rm -f "$tmp"
      return 0
    fi
  fi
  source "$cache"
}

# Sheldon plugins (adds zsh-completions to fpath, loads FSH last)
_zsh_cached_load sheldon "sheldon source" "$(command -v sheldon)"

# Atuin shell history. --disable-up-arrow leaves Up/Down to history-substring-search
# below; atuin owns Ctrl-R for full-history fuzzy search.
command -v atuin &>/dev/null && _zsh_cached_load atuin "atuin init zsh --disable-up-arrow" "$(command -v atuin)"

# History substring search keybindings
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
bindkey -M vicmd 'k' history-substring-search-up
bindkey -M vicmd 'j' history-substring-search-down

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
