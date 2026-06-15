#!/usr/bin/env bash
# install/40-symlinks.sh — the symlink mapping, single source of truth.
# Tags: symlinks
# Sourced by sync (apply) and doctor (audit). doctor reads _symlink_pairs to
# audit the exact list this applies, so the two can never drift. macOS-only
# repo — no per-OS gating.

_symlinks_tags() { printf 'symlinks\n'; }

# _symlink_pairs: emit "src|dst" lines — src relative to the repo, dst relative
# to $HOME. This list IS the symlink contract.
#
# Public API: consumed by both _symlinks_run() here (apply) and doctor (audit +
# --fix), which sources this module and reads _symlink_pairs to check/repair the
# exact set this applies. Keep the "src|dst" output shape stable.
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
git-template/hooks/pre-commit|.config/git/template/hooks/pre-commit
ssh/config|.ssh/config
ssh/1password-agent.toml|.config/1Password/ssh/agent.toml
mise.toml|.config/mise/config.toml
mise-settings.toml|.config/mise/conf.d/settings.toml
sheldon/plugins.toml|.config/sheldon/plugins.toml
starship.toml|.config/starship.toml
cmux/cmux.json|.config/cmux/cmux.json
ghostty/config|.config/ghostty/config
bat/config|.config/bat/config
atuin/config.toml|.config/atuin/config.toml
gh/config.yml|.config/gh/config.yml
gh/gh-mcp-auth-header|.local/bin/gh-mcp-auth-header
render/render-mcp-auth-header|.local/bin/render-mcp-auth-header
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
  # NB: ~/.local/bin/dot is deliberately ABSENT from this contract — it's the one
  # destination installed as a copy, not a symlink (see _install_dot_launcher).
}

# _install_dot_launcher: put `dot` on PATH as a COPY, not a symlink, plus a
# breadcrumb recording the repo path. The whole point of the resilience: a
# symlink into the repo dangles the moment the repo dir moves, so `dot` — the
# command that repairs symlinks — would itself become unrunnable, a chicken-and-
# egg you can only escape by knowing the new full path. A copy keeps running; the
# breadcrumb lets it relocate the repo with no env var. Cost of the copy: it can
# go stale when repo/dot changes — so sync re-copies every run, doctor flags drift.
_install_dot_launcher() {
  local df="${DOTFILES_DIR}" bindir="${HOME}/.local/bin" crumb
  crumb="${XDG_STATE_HOME:-${HOME}/.local/state}/dot/dir"
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '\033[0;36m  ~ would install dot launcher (copy) at %s/dot + record repo path\033[0m\n' "$bindir"
    return 0
  fi
  mkdir -p "$bindir" "$(dirname "$crumb")"
  # Reinstall when it's a symlink (legacy model → convert) or content differs
  # (cmp also fails on a dangling/absent link, which correctly forces reinstall).
  if [[ -L "${bindir}/dot" ]] || ! cmp -s "${df}/dot" "${bindir}/dot" 2> /dev/null; then
    rm -f "${bindir}/dot"
    install -m 0755 "${df}/dot" "${bindir}/dot"
    printf '\033[0;33m  \xe2\x86\x92 dot launcher (copy) installed at %s/dot\033[0m\n' "$bindir"
  else
    printf '\033[0;32m  \xe2\x9c\x93 dot launcher current (%s/dot, copy)\033[0m\n' "$bindir"
  fi
  printf '%s\n' "$df" > "$crumb"
}

_symlinks_run() {
  printf '\n==> Symlinks\n'
  local df="${DOTFILES_DIR}" src dst
  while IFS='|' read -r src dst; do
    [[ -n "$src" ]] || continue
    mkdir -p "$(dirname "${HOME}/${dst}")"
    link "${df}/${src}" "${HOME}/${dst}"
  done < <(_symlink_pairs)

  _install_dot_launcher

  # SSH needs tight perms. Skipped under --dry-run (these create/chmod ~/.ssh).
  if [[ "${DRY_RUN:-0}" != "1" ]]; then
    chmod 700 "${HOME}/.ssh" 2> /dev/null || true
    chmod 600 "${HOME}/.ssh/config" 2> /dev/null || true
    # ControlMaster sockets live here (ssh/config: ControlPath ~/.ssh/cm/%C),
    # kept out of world-writable /tmp. Must stay user-private (doctor checks 700).
    mkdir -p "${HOME}/.ssh/cm"
    chmod 700 "${HOME}/.ssh/cm" 2> /dev/null || true
  fi
}
