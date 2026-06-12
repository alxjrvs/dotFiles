#!/usr/bin/env bash
# install/80-git-maint.sh — git maintenance for the dotfiles repo.
# Tags: git
# Sourced by sync.

# Sourced by sync; not standalone — helpers (os_kind) come from sync, which
# exports them before sourcing this module.

_git_maint_tags() { printf 'git\n'; }

_git_maint_run() {
  printf '\n==> git maintenance\n'

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
