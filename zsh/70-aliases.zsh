# General
alias c="clear"
alias q="exit"

# Git
alias gs="git status"
alias gp="git push"
alias gpr='git pull --rebase'
alias gco='git checkout'
alias gd="git diff"
alias gds="git diff --staged"
alias gc="git commit"
alias ga="git add"
alias gaa="git add --all"
alias gb="git branch"
alias gl="git log --oneline -10"
alias lg="lazygit"
# git absorb: auto-fixup staged hunks against the right history commit, then squash.
alias gab="git absorb --and-rebase"

# Navigation
alias ..="cd .."
alias ...="cd ../.."
alias dots='cd "$DOTFILES_DIR"'

# Enhanced tools (eza + bat). NB: `cat` left as POSIX cat; use `b` for bat.
alias ls="eza --icons --group-directories-first"
alias la="eza --icons --group-directories-first -la --git"
alias ll="eza --icons --group-directories-first -lh --git"
alias lt="eza --icons --group-directories-first -T --level=2"
alias tree="eza --icons --group-directories-first -T"
alias b="bat --style=plain"
alias btop="btm"  # bottom (rust) covers the top/htop slot via mise (cargo:bottom)

# Editor
alias v="nvim"
alias vi="nvim"
alias vim="nvim"

# System
alias env-sync='"$DOTFILES_DIR/sync.sh"'
