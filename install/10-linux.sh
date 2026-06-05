#!/usr/bin/env bash
# install/10-linux.sh — apt packages + zsh default shell (Linux only).
# Tags: linux
# Sourced by sync; not standalone — helpers (os_kind) come from sync, which
# exports them before sourcing this module.

_linux_tags() { printf 'linux\n'; }

_linux_run() {
  if [[ "$(os_kind)" != "linux" ]]; then
    return 0
  fi

  printf '\n==> System packages\n'
  printf '\033[0;33m  \xe2\x86\x92 Updating apt and installing packages...\033[0m\n'
  sudo apt update -y
  sudo apt install -y zsh git curl
  printf '\033[0;32m  \xe2\x9c\x93 System packages installed\033[0m\n'

  printf '\n==> Default shell\n'
  local current_shell
  current_shell=$(basename "${SHELL:-}")
  if [[ "$current_shell" == "zsh" ]]; then
    printf '\033[0;32m  \xe2\x9c\x93 zsh is already the default shell\033[0m\n'
  else
    printf '\033[0;33m  \xe2\x86\x92 Setting zsh as default shell...\033[0m\n'
    local zsh_path
    zsh_path=$(command -v zsh 2> /dev/null || true)
    local user="${USER:-}"
    sudo chsh -s "$zsh_path" "$user" 2> /dev/null || true
    printf '\033[0;33m  \xe2\x86\x92 zsh set as default (takes effect on next login)\033[0m\n'
  fi

  local gitconfig_local="${HOME}/.gitconfig.local"
  if [[ ! -e "$gitconfig_local" ]]; then
    printf '[credential]\n\thelper = cache\n' > "$gitconfig_local"
    printf '\033[0;32m  \xe2\x9c\x93 Created ~/.gitconfig.local with credential helper = cache\033[0m\n'
  else
    printf '\033[0;32m  \xe2\x9c\x93 ~/.gitconfig.local already exists\033[0m\n'
  fi
}
