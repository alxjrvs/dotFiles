# Thin .zshrc — actual config lives in fragments under ~/.config/zsh/,
# loaded in numeric order. Edit those, not this file.
ZSH_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"
for _f in "$ZSH_CONFIG_DIR"/[0-9]*.zsh; do
  [ -f "$_f" ] && source "$_f"
done
unset _f
