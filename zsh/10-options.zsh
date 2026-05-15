# Autocorrection
setopt CORRECT

# Power-user defaults
setopt EXTENDED_GLOB        # ^pat, (a|b), <1-10>, glob qualifiers like (.) (/)
setopt INTERACTIVE_COMMENTS # # comments allowed in interactive shell (paste-friendly)
setopt NO_BEEP              # silent on completion errors / EOL
setopt NO_FLOWCONTROL       # frees Ctrl-S/Q for ZLE + fzf bindings

# History — atuin sync v2 is the source of truth; native history covers
# arrow-key recall only. 10k is plenty without doubling disk I/O.
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY HIST_IGNORE_ALL_DUPS HIST_IGNORE_SPACE
setopt HIST_VERIFY
setopt EXTENDED_HISTORY
setopt HIST_REDUCE_BLANKS
