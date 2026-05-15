# Completions — must run after fpath extensions (sheldon adds zsh-completions
# in 30-plugins.zsh) and BEFORE plugins that wrap ZLE.
autoload -Uz compinit
if [[ -n ${ZDOTDIR:-$HOME}/.zcompdump(Nm+1) ]]; then
  compinit
else
  compinit -C
fi

# fzf-tab requires menu off (or no-select) — it owns the rendering.
zstyle ':completion:*' menu no
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*:git-checkout:*' sort false

# fzf-tab — preview window for cd/file completions.
zstyle ':fzf-tab:*' use-fzf-default-opts yes
zstyle ':fzf-tab:*' switch-group '<' '>'
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --icons --color=always $realpath'
zstyle ':fzf-tab:complete:*:*' fzf-preview \
  '[[ -d $realpath ]] && eza -1 --icons --color=always $realpath \
   || bat --color=always --style=plain --line-range :40 $realpath 2>/dev/null \
   || echo $realpath'

# Carapace — drop-in completions for ~600 CLIs. Loads after compinit;
# the cached-init pattern keeps shell startup fast.
if command -v carapace &>/dev/null; then
  export CARAPACE_BRIDGES='zsh,fish,bash,inshellisense'
  _zsh_cached_load carapace "carapace _carapace" "$(command -v carapace)"
fi
