#!/usr/bin/env bash
# install/80-git-maint.sh — git maintenance for the dotfiles repo.
# Tags: git
# Sourced by sync.

# Sourced by sync; not standalone — helpers (os_kind) come from sync, which
# exports them before sourcing this module.

_git_maint_tags() { printf 'git\n'; }

_git_maint_run() {
  printf '\n==> git maintenance\n'

  # Seed ~/.gitconfig.local if absent. The tracked .gitconfig unconditionally
  # `[include]`s it, and git maintenance (below) writes maintenance.repo there.
  # On Linux, install/10-linux.sh creates it; on a fresh Mac nothing else does,
  # so this module (which owns git setup on the macOS path) owns the seed too.
  # git tolerates a missing include, so this is hygiene rather than a hard dep.
  local gitconfig_local="${HOME}/.gitconfig.local"
  if [[ ! -e "$gitconfig_local" ]]; then
    if printf '# ~/.gitconfig.local — machine-local git overrides (not tracked).\n' \
      > "$gitconfig_local" 2> /dev/null; then
      printf '\033[0;33m  \xe2\x86\x92 seeded %s\033[0m\n' "${gitconfig_local/#$HOME\//~/}"
    else
      printf '\033[0;33m  \xe2\x9a\xa0 could not seed %s (continuing)\033[0m\n' \
        "${gitconfig_local/#$HOME\//~/}" >&2
    fi
  fi

  # GIT_CONFIG_GLOBAL redirects the maintenance.repo write to
  # ~/.gitconfig.local so the tracked .gitconfig stays portable.
  if GIT_CONFIG_GLOBAL="${HOME}/.gitconfig.local" \
    git -C "${DOTFILES_DIR}" maintenance start \
    > /dev/null 2>&1; then
    printf '\033[0;32m  \xe2\x9c\x93 git maintenance scheduled for %s\033[0m\n' "${DOTFILES_DIR}"
  else
    printf '\033[2m  - git maintenance already scheduled or not supported\033[0m\n'
  fi
}
