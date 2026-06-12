#!/usr/bin/env bash
# install/40-symlinks.sh — the symlink mapping, single source of truth.
# Tags: symlinks
# Sourced by sync (apply) and doctor (audit); both export link() and set
# __DOT_SYNC_SOURCED. doctor reads _symlink_pairs to audit the exact list this
# applies, so the two can never drift. macOS-only repo — no per-OS gating.

_symlinks_tags() { printf 'symlinks\n'; }

# _symlink_pairs: emit "src|dst" lines — src relative to the repo, dst relative
# to $HOME. This list IS the symlink contract.
_symlink_pairs() {
  cat << 'PAIRS'
.zshrc|.zshrc
.zprofile|.zprofile
.zshenv|.zshenv
.hushlogin|.hushlogin
.gitconfig|.gitconfig
.gitmessage|.gitmessage
.gitignore|.gitignore
.editorconfig|.editorconfig
.ripgreprc|.ripgreprc
.fdignore|.fdignore
dot|.local/bin/dot
git-template/hooks/pre-commit|.config/git/template/hooks/pre-commit
ssh/config|.ssh/config
ssh/1password-agent.toml|.config/1Password/ssh/agent.toml
mise.toml|.config/mise/config.toml
sheldon/plugins.toml|.config/sheldon/plugins.toml
starship.toml|.config/starship.toml
ghostty/config|.config/ghostty/config
bat/config|.config/bat/config
atuin/config.toml|.config/atuin/config.toml
gh/config.yml|.config/gh/config.yml
gh/gh-mcp-auth-header|.local/bin/gh-mcp-auth-header
nvim/init.lua|.config/nvim/init.lua
karabiner/karabiner.json|.config/karabiner/karabiner.json
dot-claude/CLAUDE.md|.claude/CLAUDE.md
dot-claude/settings.json|.claude/settings.json
PAIRS
  # zsh fragments — numeric-prefixed *.zsh, expanded dynamically.
  local f name
  for f in "${DOTFILES_DIR:-}"/zsh/[0-9]*.zsh; do
    [[ -f "$f" ]] || continue
    name=$(basename "$f")
    printf 'zsh/%s|.config/zsh/%s\n' "$name" "$name"
  done
}

_symlinks_run() {
  printf '\n==> Symlinks\n'
  local df="${DOTFILES_DIR}" src dst
  while IFS='|' read -r src dst; do
    [[ -n "$src" ]] || continue
    mkdir -p "$(dirname "${HOME}/${dst}")"
    link "${df}/${src}" "${HOME}/${dst}"
  done < <(_symlink_pairs)

  # SSH needs tight perms.
  chmod 700 "${HOME}/.ssh" 2> /dev/null || true
  chmod 600 "${HOME}/.ssh/config" 2> /dev/null || true
}
