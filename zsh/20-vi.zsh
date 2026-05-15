# Vi keybindings
bindkey -v
KEYTIMEOUT=1

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
