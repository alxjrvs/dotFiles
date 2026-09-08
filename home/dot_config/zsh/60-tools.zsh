# fzf shell integration (modern)
eval "$(fzf --zsh)"

# Re-take Tab for fzf-tab, because `fzf --zsh` just bound ^I to fzf-completion. fzf-tab must
# be the last thing to bind ^I and must follow compinit, and sheldon loads it before both
# (30-plugins.zsh); without this line Tab still completes, so the loss is invisible. Guarded,
# so a machine where sheldon has not cloned the plugin yet still gets a working shell.
(( $+functions[enable-fzf-tab] )) && enable-fzf-tab

# Atuin shell history — Ctrl-R fuzzy search. Must load AFTER fzf: both bind
# Ctrl-R and whichever inits last wins the binding; atuin's synced/encrypted
# history is meant to be the source of truth (see zsh/10-options.zsh), so it
# has to override fzf's plain-history binding here, not the reverse.
# --disable-up-arrow keeps Up/Down as plain zsh history navigation instead of
# opening atuin's search on every Up.
eval "$(atuin init zsh --disable-up-arrow)"

export FZF_DEFAULT_OPTS='--layout=reverse --border --height=40% --color=bg+:#3b4252,bg:#2e3440,spinner:#81a1c1,hl:#a3be8c,fg:#d8dee9,header:#a3be8c,info:#ebcb8b,pointer:#81a1c1,marker:#81a1c1,prompt:#81a1c1'
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow'
export FZF_CTRL_T_OPTS="--preview 'bat --color=always {}' --preview-window right:50%"
export FZF_ALT_C_OPTS="--preview 'eza --icons -T {} | head -20'"
export FZF_ALT_C_COMMAND='fd --type d --hidden --follow'

# zoxide — frecency `cd`. `z foo` jumps to the most-frecent dir matching "foo";
# `zi foo` opens an fzf picker over matches (inherits FZF_DEFAULT_OPTS above).
# Loaded after fzf so the `zi` widget reuses the same fzf config.
eval "$(zoxide init zsh)"

# mise (tool version manager)
eval "$(mise activate zsh)"
