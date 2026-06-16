#!/usr/bin/env bash
# install/85-lefthook.sh — lefthook install for the dotfiles repo.
# Tags: lefthook
# Sourced by sync; not standalone — helpers (os_kind) come from sync, which
# exports them before sourcing this module.

_lefthook_tags() { printf 'lefthook\n'; }

_lefthook_run() {
  printf '\n==> Lefthook (this repo)\n'

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '\033[0;36m  ~ [dry-run] would run lefthook install in %s\033[0m\n' "${DOTFILES_DIR}"
    return 0
  fi

  if ! command -v lefthook > /dev/null 2>&1; then
    printf '\033[0;33m  \xe2\x86\x92 lefthook not found — should have been installed by mise (mise.toml)\033[0m\n'
    return 0
  fi

  # A repo move leaves local core.hooksPath pinned to the OLD absolute path, so
  # lefthook refuses to install ("Custom hooks paths are not supported"). This
  # repo always uses the default .git/hooks (lefthook manages them there), so any
  # local core.hooksPath is cruft — drop it before install so a move self-heals.
  if git -C "${DOTFILES_DIR}" config --local --get core.hooksPath > /dev/null 2>&1; then
    git -C "${DOTFILES_DIR}" config --local --unset-all core.hooksPath 2> /dev/null || true
    printf '\033[0;36m  \xe2\x9c\x82 cleared stale local core.hooksPath\033[0m\n'
  fi

  # lefthook has no --working-directory flag; it operates on the cwd.
  if (cd "${DOTFILES_DIR}" && lefthook install) > /dev/null 2>&1; then
    printf '\033[0;32m  \xe2\x9c\x93 lefthook hooks installed in %s/.git/hooks/\033[0m\n' "${DOTFILES_DIR}"
  else
    printf '\033[0;33m  \xe2\x86\x92 lefthook install failed — check '"'"'lefthook install --force'"'"' manually\033[0m\n'
  fi
}
