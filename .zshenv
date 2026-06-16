# Dotfiles root — used by dot/doctor/sync and the `dots` alias. Self-locating:
# resolves this (symlinked) file back to its source, so any clone location works
# with no hardcoded path. Exported so every shell context inherits it.
#
# Honor an inherited DOTFILES_DIR only when it still points at a real repo (has a
# Brewfile). A stale value from a moved clone otherwise sticks across nested
# shells (the env outlives the move) and breaks `dots` + any direct sync/doctor —
# the same validity check the `dot` dispatcher makes before trusting the env.
[[ -f "${DOTFILES_DIR:-}/Brewfile" ]] || export DOTFILES_DIR="${${(%):-%x}:A:h}"

# Dedup PATH/path entries and keep the first (highest-priority) occurrence, so
# the mise shims prepend below survives macOS path_helper and nested shells.
typeset -U path PATH

# mise shims — available in all shell contexts (hooks, editors, subprocesses)
export PATH="$HOME/.local/share/mise/shims:$PATH"
