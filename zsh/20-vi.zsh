# Vi keybindings
bindkey -v
KEYTIMEOUT=10

# Vi mode cursor shape
function zle-keymap-select {
  if [[ $KEYMAP == vicmd ]]; then
    echo -ne '\e[1 q'  # block cursor in normal mode
  else
    echo -ne '\e[1 q'  # blinking block cursor in insert mode
  fi
}
zle -N zle-keymap-select

# Blinking block cursor on new prompt
zle-line-init() { echo -ne '\e[1 q' }
zle -N zle-line-init
