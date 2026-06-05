# Completions — must run after fpath extensions (sheldon adds zsh-completions
# in 30-plugins.zsh) and BEFORE plugins that wrap ZLE.
autoload -Uz compinit
# Glob qualifiers don't expand inside [[ ]]; evaluate via an array assignment.
# `N` = nullglob (empty when no match). `_fresh` matches the dump only when it
# exists AND is newer than 24h (mh-24 = mtime within the last 24 hours). Empty
# array ⇒ dump missing or stale ⇒ run the full compinit (with security audit);
# non-empty ⇒ skip the audit with -C for a faster startup.
_zcompdump="${ZDOTDIR:-$HOME}/.zcompdump"
_zcompdump_fresh=("$_zcompdump"(Nmh-24))
if (( ${#_zcompdump_fresh} )); then
  compinit -C
else
  compinit
fi
unset _zcompdump _zcompdump_fresh

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

# Specialized previews: git branch context, git diff, process info, ssh resolution.
zstyle ':fzf-tab:complete:git-(checkout|switch|log|show):*' fzf-preview \
  'git log --oneline --color=always --decorate $word 2>/dev/null | head -50'
zstyle ':fzf-tab:complete:git-(diff|restore|add):*' fzf-preview \
  'git diff --color=always -- $word 2>/dev/null | head -200'
zstyle ':fzf-tab:complete:kill:argument-rest' fzf-preview \
  'ps -p $word -o pid,ppid,user,start,command 2>/dev/null'
zstyle ':fzf-tab:complete:ssh:argument-rest' fzf-preview \
  'echo "DNS:"; dig +short $word 2>/dev/null; echo; echo "ssh -G:"; ssh -G $word 2>/dev/null | head -20'

# Carapace — drop-in completions for ~600 CLIs. Loads after compinit;
# the cached-init pattern keeps shell startup fast.
if command -v carapace &>/dev/null; then
  export CARAPACE_BRIDGES='zsh,fish,bash,inshellisense'
  _zsh_cached_load carapace "carapace _carapace" "$(command -v carapace)"
fi
