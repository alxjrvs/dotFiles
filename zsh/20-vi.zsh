# Vi keybindings
bindkey -v
KEYTIMEOUT=1

# Disable terminal flow control (frees Ctrl-S/Q for ZLE + fzf).
# NO_FLOWCONTROL setopt + this stty cover both zsh's ZLE layer and the kernel tty.
stty -ixon 2>/dev/null

# Vi mode cursor shape: steady block in normal, blinking bar in insert.
# DECSCUSR codes: 1=blink block, 2=steady block, 5=blink bar, 6=steady bar.
function zle-keymap-select {
  if [[ $KEYMAP == vicmd ]]; then
    echo -ne '\e[2 q'
  else
    echo -ne '\e[5 q'
  fi
}
zle -N zle-keymap-select

# Reset to insert-mode cursor on every new prompt
zle-line-init() { echo -ne '\e[5 q' }
zle -N zle-line-init
