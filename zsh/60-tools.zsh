# fzf shell integration (modern)
eval "$(fzf --zsh)"
export FZF_DEFAULT_OPTS='--layout=reverse --border --height=40% --color=bg+:#3b4252,bg:#2e3440,spinner:#81a1c1,hl:#a3be8c,fg:#d8dee9,header:#a3be8c,info:#ebcb8b,pointer:#81a1c1,marker:#81a1c1,prompt:#81a1c1'
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_OPTS="--preview 'bat --color=always {}' --preview-window right:50%"
export FZF_ALT_C_OPTS="--preview 'eza --icons -T {} | head -20'"

# zoxide — frecency `cd`. `z foo` jumps to the most-frecent dir matching "foo";
# `zi foo` opens an fzf picker over matches (inherits FZF_DEFAULT_OPTS above).
# Loaded after fzf so the `zi` widget reuses the same fzf config.
eval "$(zoxide init zsh)"

# mise (tool version manager)
eval "$(mise activate zsh)"

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"
