# Dotfiles root — referenced by scripts/, prompt code, statusline, hooks.
# Exported here so all shell contexts (subprocesses, sh-invoked scripts) inherit it.
export DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotFiles}"

# mise shims — available in all shell contexts (hooks, editors, subprocesses)
export PATH="$HOME/.local/share/mise/shims:$PATH"
