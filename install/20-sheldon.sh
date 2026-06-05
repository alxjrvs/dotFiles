#!/usr/bin/env bash
# install/20-sheldon.sh — Sheldon binary install + plugin lock.
# Tags: sheldon
# Sourced by sync; not standalone — helpers (os_kind) come from sync, which
# exports them before sourcing this module.

_sheldon_tags() { printf 'sheldon\n'; }

_sheldon_run() {
  printf '\n==> Sheldon\n'
  if command -v sheldon > /dev/null 2>&1; then
    printf '\033[0;32m  \xe2\x9c\x93 Sheldon installed\033[0m\n'
  elif [[ "$(os_kind)" == "darwin" ]]; then
    printf '\033[0;31m  \xe2\x9c\x97 Sheldon not found — should have been installed by brew bundle\033[0m\n' >&2
  elif [[ "$(os_kind)" == "linux" ]]; then
    printf '\033[0;33m  \xe2\x86\x92 Installing Sheldon...\033[0m\n'
    curl --proto '=https' -fLsS https://rossmacarthur.github.io/install/crate.sh |
      bash -s -- --repo rossmacarthur/sheldon --to ~/.local/bin
    printf '\033[0;32m  \xe2\x9c\x93 Sheldon installed\033[0m\n'
  fi

  printf '\n==> Sheldon plugins\n'
  printf '\033[0;33m  \xe2\x86\x92 Updating Sheldon plugins...\033[0m\n'
  if sheldon lock --update 2> /dev/null; then
    printf '\033[0;32m  \xe2\x9c\x93 Sheldon plugins up to date\033[0m\n'
  else
    printf '\033[0;33m  \xe2\x86\x92 Sheldon lock failed or timed out (may be offline) — skipping\033[0m\n'
  fi
}
