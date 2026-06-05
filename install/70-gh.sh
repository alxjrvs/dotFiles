#!/usr/bin/env bash
# install/70-gh.sh — GitHub CLI extensions (gated on auth).
# Tags: gh
# Sourced by sync; not standalone — helpers (os_kind) come from sync, which
# exports them before sourcing this module.

_gh_tags() { printf 'gh\n'; }

_gh_run() {
  printf '\n==> GitHub CLI\n'

  if ! gh auth status > /dev/null 2>&1; then
    printf '\033[0;33m  \xe2\x86\x92 Not authenticated — run: gh auth login\033[0m\n'
    return 0
  fi
  printf '\033[0;32m  \xe2\x9c\x93 gh authenticated\033[0m\n'

  local installed
  installed=$(gh extension list 2> /dev/null || true)

  local repo name
  while IFS=' ' read -r repo name; do
    if printf '%s\n' "$installed" | grep -qF "$repo"; then
      printf '\033[2m  - %s extension already installed\033[0m\n' "$name"
    else
      printf '\033[0;33m  \xe2\x86\x92 Installing %s extension...\033[0m\n' "$name"
      if gh extension install "$repo" 2> /dev/null; then
        printf '\033[0;32m  \xe2\x9c\x93 %s installed\033[0m\n' "$name"
      else
        printf '\033[0;33m  \xe2\x86\x92 %s install failed\033[0m\n' "$name"
      fi
    fi
  done << 'EOF'
dlvhdr/gh-dash gh-dash
meiji163/gh-notify gh-notify
actions/gh-actions-cache gh-actions-cache
EOF
}
