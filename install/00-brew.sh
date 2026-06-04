#!/usr/bin/env bash
# install/00-brew.sh — Homebrew install + bundle (Darwin only).
# Ports sync.rs: step_brew.
# Tags: brew
# Sourced by sync; also independently runnable.

# ── Self-contained helpers (only defined when not already provided by sync) ───
if [[ -z "${__DOT_SYNC_SOURCED:-}" ]]; then
  os_kind() {
    case "$(uname -s)" in
      Darwin) printf 'darwin\n' ;;
      Linux) printf 'linux\n' ;;
      *) printf 'unknown\n' ;;
    esac
  }
  host_id() {
    local forced="${DOTFILES_HOST:-}"
    if [[ -n "$forced" ]]; then
      case "${forced,,}" in
        air)
          printf 'air\n'
          return 0
          ;;
        pro)
          printf 'pro\n'
          return 0
          ;;
      esac
    fi
    local hostname=""
    if command -v scutil > /dev/null 2>&1; then
      hostname=$(scutil --get LocalHostName 2> /dev/null || true)
    fi
    local lower="${hostname,,}"
    if [[ "$lower" == *air* ]]; then
      printf 'air\n'
    elif [[ "$lower" == *pro* ]]; then
      printf 'pro\n'
    else
      printf 'unknown\n'
    fi
  }
fi

_brew_tags() { printf 'brew\n'; }

_brew_run() {
  if [[ "$(os_kind)" != "darwin" ]]; then
    return 0
  fi

  printf '\n==> Homebrew\n'

  if command -v brew > /dev/null 2>&1; then
    printf '\033[0;32m  \xe2\x9c\x93 Homebrew installed\033[0m\n'
  else
    printf '\033[0;33m  \xe2\x86\x92 Installing Homebrew...\033[0m\n'
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
  brew bundle --file="${DOTFILES_DIR}/Brewfile" --no-upgrade
  printf '\033[0;32m  \xe2\x9c\x93 Brewfile dependencies up to date\033[0m\n'

  # Per-host overlay.
  local host_id_val
  host_id_val=$(host_id)
  if [[ "$host_id_val" != "unknown" ]]; then
    local overlay="${DOTFILES_DIR}/Brewfile.${host_id_val}"
    if [[ -f "$overlay" ]]; then
      printf '\033[0;33m  \xe2\x86\x92 Installing host overlay (Brewfile.%s)...\033[0m\n' "$host_id_val"
      brew bundle --file="$overlay" --no-upgrade
      printf '\033[0;32m  \xe2\x9c\x93 Brewfile.%s dependencies up to date\033[0m\n' "$host_id_val"
    fi
  fi

  # Docker Desktop / docker formula collision.
  local cask_docker=0 formula_docker=0
  brew list --cask docker-desktop > /dev/null 2>&1 && cask_docker=1 || true
  brew list --formula docker > /dev/null 2>&1 && formula_docker=1 || true
  if [[ "$cask_docker" == "1" && "$formula_docker" == "1" ]]; then
    printf '\033[0;33m  \xe2\x86\x92 Removing docker formula (conflicts with Docker Desktop)...\033[0m\n'
    brew uninstall --formula docker 2> /dev/null || true
    brew uninstall --formula docker-completion 2> /dev/null || true
    printf '\033[0;32m  \xe2\x9c\x93 docker formula removed — Docker Desktop provides the CLI\033[0m\n'
  fi
}
