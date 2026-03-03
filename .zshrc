export EDITOR="nvim"

# Autocorrection
setopt CORRECT

# History
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE

# Vi keybindings
bindkey -v
KEYTIMEOUT=1

# Homebrew completions
fpath+=("$(brew --prefix)/share/zsh/site-functions")

# Sheldon plugins (adds zsh-completions to fpath)
eval "$(sheldon source)"

# Syntax highlighting theme (GitHub Dark)
typeset -A ZSH_HIGHLIGHT_STYLES
ZSH_HIGHLIGHT_STYLES[default]='fg=#e6edf3'
ZSH_HIGHLIGHT_STYLES[command]='fg=white'
ZSH_HIGHLIGHT_STYLES[alias]='fg=#7ee787'
ZSH_HIGHLIGHT_STYLES[function]='fg=#d2a8ff'
ZSH_HIGHLIGHT_STYLES[builtin]='fg=#79c0ff'
ZSH_HIGHLIGHT_STYLES[reserved-word]='fg=#ff7b72'
ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=#f85149'
ZSH_HIGHLIGHT_STYLES[precommand]='fg=#d2a8ff,underline'
ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=#a5d6ff'
ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=#a5d6ff'
ZSH_HIGHLIGHT_STYLES[dollar-quoted-argument]='fg=#a5d6ff'
ZSH_HIGHLIGHT_STYLES[dollar-double-quoted-argument]='fg=#ffa657'
ZSH_HIGHLIGHT_STYLES[back-double-quoted-argument]='fg=#ffa657'
ZSH_HIGHLIGHT_STYLES[single-hyphen-option]='fg=#8b949e'
ZSH_HIGHLIGHT_STYLES[double-hyphen-option]='fg=#8b949e'
ZSH_HIGHLIGHT_STYLES[globbing]='fg=#ffa657'
ZSH_HIGHLIGHT_STYLES[redirection]='fg=#79c0ff'
ZSH_HIGHLIGHT_STYLES[commandseparator]='fg=#79c0ff'
ZSH_HIGHLIGHT_STYLES[assign]='fg=#ffa657'
ZSH_HIGHLIGHT_STYLES[comment]='fg=#8b949e,italic'
ZSH_HIGHLIGHT_STYLES[path]='fg=#e6edf3,underline'

# Completions (must be after fpath extensions and sheldon)
autoload -Uz compinit
if [ "$(find ~/.zcompdump -mtime +1 2>/dev/null)" ]; then
  compinit
else
  compinit -C
fi

# Starship prompt
eval "$(starship init zsh)"

# fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# zoxide
eval "$(zoxide init zsh)"

# Aliases
alias c="clear"
alias q="exit"
alias gs="git status"
alias gp="git push"
alias gpr='git pull --rebase'

# asdf default packages
export ASDF_NPM_DEFAULT_PACKAGES_FILE=~/.default-npm-packages

# Colored man pages
export LESS_TERMCAP_mb=$'\e[1;31m'
export LESS_TERMCAP_md=$'\e[1;36m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_so=$'\e[1;44;33m'
export LESS_TERMCAP_ue=$'\e[0m'
export LESS_TERMCAP_us=$'\e[1;32m'

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"

