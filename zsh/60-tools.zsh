# fzf shell integration (modern)
eval "$(fzf --zsh)"

# Re-take Tab for fzf-tab, because the line above just took it away.
#
# fzf-tab is loaded by sheldon in 30-plugins.zsh, which is too early on both counts its README
# names: it must load AFTER compinit (40-completions.zsh), and it must be "the last plugin to
# bind ^I". `fzf --zsh` above binds ^I to fzf-completion, so fzf-tab lost every time — its widget
# was defined and simply never reachable, which is why this was invisible: Tab still completed,
# just with plain fzf-completion, and the entire fzf-tab zstyle block in 40-completions.zsh
# (git-log/git-diff/ps/ssh previews, switch-group) silently did nothing.
#
# Verified: `zsh -i -c 'bindkey "^I"'` reported `fzf-completion` before this line and
# `fzf-tab-complete` after it.
#
# Guarded, so a machine where sheldon hasn't cloned the plugin yet still gets a working shell
# rather than an error on every startup.
(( $+functions[enable-fzf-tab] )) && enable-fzf-tab

# Atuin shell history — Ctrl-R fuzzy search. Must load AFTER fzf: both bind
# Ctrl-R and whichever inits last wins the binding; atuin's synced/encrypted
# history is meant to be the source of truth (see zsh/10-options.zsh), so it
# has to override fzf's plain-history binding here, not the reverse.
# --disable-up-arrow keeps Up/Down as plain zsh history navigation instead of
# opening atuin's search on every Up.
eval "$(atuin init zsh --disable-up-arrow)"

export FZF_DEFAULT_OPTS='--layout=reverse --border --height=40% --color=bg+:#3b4252,bg:#2e3440,spinner:#81a1c1,hl:#a3be8c,fg:#d8dee9,header:#a3be8c,info:#ebcb8b,pointer:#81a1c1,marker:#81a1c1,prompt:#81a1c1'
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_OPTS="--preview 'bat --color=always {}' --preview-window right:50%"
export FZF_ALT_C_OPTS="--preview 'eza --icons -T {} | head -20'"
export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'

# zoxide — frecency `cd`. `z foo` jumps to the most-frecent dir matching "foo";
# `zi foo` opens an fzf picker over matches (inherits FZF_DEFAULT_OPTS above).
# Loaded after fzf so the `zi` widget reuses the same fzf config.
eval "$(zoxide init zsh)"

# mise (tool version manager)
eval "$(mise activate zsh)"
