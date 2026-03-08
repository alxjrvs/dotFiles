export EDITOR="nvim"

# Machine-local secrets (not in git)
[[ -f ~/.secrets ]] && source ~/.secrets

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
command -v brew &>/dev/null && fpath+=("$(brew --prefix)/share/zsh/site-functions")

# Sheldon plugins (adds zsh-completions to fpath)
eval "$(sheldon source)"

# Syntax highlighting theme (Jack Kirby CMYK)
typeset -A ZSH_HIGHLIGHT_STYLES
ZSH_HIGHLIGHT_STYLES[default]='fg=#e6edf3'
ZSH_HIGHLIGHT_STYLES[command]='fg=#4db8cc'
ZSH_HIGHLIGHT_STYLES[alias]='fg=#4db8cc'
ZSH_HIGHLIGHT_STYLES[function]='fg=#d06cb8'
ZSH_HIGHLIGHT_STYLES[builtin]='fg=#4db8cc'
ZSH_HIGHLIGHT_STYLES[reserved-word]='fg=#d06cb8'
ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=#e05050'
ZSH_HIGHLIGHT_STYLES[precommand]='fg=#d06cb8,underline'
ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=#d4b84a'
ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=#d4b84a'
ZSH_HIGHLIGHT_STYLES[dollar-quoted-argument]='fg=#d4b84a'
ZSH_HIGHLIGHT_STYLES[dollar-double-quoted-argument]='fg=#d48040'
ZSH_HIGHLIGHT_STYLES[back-double-quoted-argument]='fg=#d48040'
ZSH_HIGHLIGHT_STYLES[single-hyphen-option]='fg=#8b949e'
ZSH_HIGHLIGHT_STYLES[double-hyphen-option]='fg=#8b949e'
ZSH_HIGHLIGHT_STYLES[globbing]='fg=#d48040'
ZSH_HIGHLIGHT_STYLES[redirection]='fg=#4db8cc'
ZSH_HIGHLIGHT_STYLES[commandseparator]='fg=#4db8cc'
ZSH_HIGHLIGHT_STYLES[assign]='fg=#d4b84a'
ZSH_HIGHLIGHT_STYLES[comment]='fg=#8b949e,italic'
ZSH_HIGHLIGHT_STYLES[path]='fg=#e6edf3,underline'

# Completions (must be after fpath extensions and sheldon)
autoload -Uz compinit
if [ "$(find ~/.zcompdump -mtime +1 2>/dev/null)" ]; then
  compinit
else
  compinit -C
fi

if command -v starship &>/dev/null; then
  # In tmux, the status bar already shows dir/git/time — use minimal prompt
  [[ -n "$TMUX" ]] && export STARSHIP_CONFIG="$HOME/.config/starship-tmux.toml"
  # Starship prompt
  eval "$(starship init zsh)"

  # Transient prompt — collapse previous prompts to just the character
  # Skip inside tmux: prompt is already minimal and no transient profile is defined
  if [[ -z "$TMUX" ]]; then
    function transient-prompt-precmd {
      TRAPINT() { transient-prompt-func; return $(( 128 + $1 )) }
    }
    function transient-prompt-func {
      local STARSHIP_TRANSIENT
      STARSHIP_TRANSIENT="$(starship prompt --profile transient)"
      PROMPT="$STARSHIP_TRANSIENT" RPROMPT="" zle .reset-prompt
    }
    autoload -Uz add-zsh-hook add-zle-hook-widget
    add-zsh-hook precmd transient-prompt-precmd
    add-zle-hook-widget zle-line-finish transient-prompt-func
  fi
fi

# fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# zoxide
command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"

# Aliases
alias c="clear"
alias q="exit"
alias gs="git status"
alias gp="git push"
alias gpr='git pull --rebase'
alias gco='git checkout'
alias ..="cd .."
alias v="nvim"
alias vi="nvim"
alias vim="nvim"
alias env-sync="~/dotFiles/sync.sh"

# asdf default packages
command -v asdf &>/dev/null && export ASDF_NPM_DEFAULT_PACKAGES_FILE=~/.default-npm-packages

# Colored man pages (CMYK)
export LESS_TERMCAP_mb=$'\e[1;35m'
export LESS_TERMCAP_md=$'\e[1;36m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_so=$'\e[1;33;46m'
export LESS_TERMCAP_ue=$'\e[0m'
export LESS_TERMCAP_us=$'\e[1;35m'

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"

