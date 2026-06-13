#!/usr/bin/env bash
# install/00-brew.sh — Homebrew install + bundle (Darwin only).
# Tags: brew
# Sourced by sync; not standalone — helpers (os_kind) come from sync,
# which exports them before sourcing this module.

_brew_tags() { printf 'brew\n'; }

_brew_run() {
  if [[ "$(os_kind)" != "darwin" ]]; then
    return 0
  fi

  printf '\n==> Homebrew\n'

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '\033[0;36m  ~ [dry-run] would ensure Homebrew and run brew bundle (--upgrade also updates/upgrades/cleans)\033[0m\n'
    return 0
  fi

  if command -v brew > /dev/null 2>&1; then
    printf '\033[0;32m  \xe2\x9c\x93 Homebrew installed\033[0m\n'
  else
    printf '\033[0;33m  \xe2\x86\x92 Installing Homebrew...\033[0m\n'
    # Accepted residual risk: the upstream installer is piped to bash without a
    # checksum. Homebrew publishes no stable per-release hash for install.sh (the
    # HEAD URL moves), so pinning isn't possible; trust is anchored in HTTPS +
    # GitHub. Runs once on a fresh machine, only when `brew` is absent.
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  if [[ "${SYNC_UPGRADE:-0}" == "1" ]]; then
    printf '\033[0;33m  \xe2\x86\x92 Updating Homebrew...\033[0m\n'
    brew update
    printf '\033[0;33m  \xe2\x86\x92 Upgrading formulae and casks...\033[0m\n'
    brew upgrade
    brew upgrade --cask 2> /dev/null || true
    printf '\033[0;33m  \xe2\x86\x92 Removing outdated versions...\033[0m\n'
    brew cleanup --prune=all
  else
    printf '\033[2m  - Skipping brew update/upgrade/cleanup (pass --upgrade to run)\033[0m\n'
  fi

  printf '\n==> Brew Bundle\n'

  # Xcode CLT check.
  if ! xcode-select --version > /dev/null 2>&1; then
    printf '\033[0;31m  \xe2\x9c\x97 Xcode Command Line Tools not found\033[0m\n' >&2
    xcode-select --install 2> /dev/null || true
    printf '\033[0;31m  \xe2\x9c\x97 Xcode CLT installer opened — approve the dialog, then re-run\033[0m\n' >&2
    return 1
  fi

  printf '\033[0;33m  \xe2\x86\x92 Installing Brewfile dependencies (skipping upgrades)...\033[0m\n'
  if brew bundle --file="${DOTFILES_DIR}/Brewfile" --no-upgrade; then
    printf '\033[0;32m  \xe2\x9c\x93 Brewfile dependencies up to date\033[0m\n'
  else
    printf '\033[0;31m  \xe2\x9c\x97 brew bundle failed — system is partially provisioned\033[0m\n' >&2
    return 1
  fi
}
