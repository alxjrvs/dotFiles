# fzf shell integration (modern)
if command -v fzf &>/dev/null; then
  _zsh_cached_load fzf "fzf --zsh" "$(command -v fzf)"
fi
export FZF_DEFAULT_OPTS='--layout=reverse --border --height=40% --color=bg+:#3b4252,bg:#2e3440,spinner:#81a1c1,hl:#a3be8c,fg:#d8dee9,header:#a3be8c,info:#ebcb8b,pointer:#81a1c1,marker:#81a1c1,prompt:#81a1c1'
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_OPTS="--preview 'bat --color=always {}' --preview-window right:50%"
export FZF_ALT_C_OPTS="--preview 'eza --icons -T {} | head -20'"

# mise (tool version manager)
command -v mise &>/dev/null && _zsh_cached_load mise "mise activate zsh" "$(command -v mise)"

# direnv (per-directory environment)
command -v direnv &>/dev/null && _zsh_cached_load direnv "direnv hook zsh" "$(command -v direnv)"

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"
