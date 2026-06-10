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

  # Extensions are PINNED to a tag/SHA: an unpinned install tracks the repo
  # default branch — the widest unreviewed-RCE surface on this machine, with
  # keychain-token access. Bump the pin deliberately, not via upstream push.
  local repo name pin
  while IFS=' ' read -r repo name pin; do
    if printf '%s\n' "$installed" | grep -qF "$repo"; then
      printf '\033[2m  - %s extension already installed\033[0m\n' "$name"
    else
      printf '\033[0;33m  \xe2\x86\x92 Installing %s extension (pinned %s)...\033[0m\n' "$name" "$pin"
      if gh extension install "$repo" --pin "$pin" 2> /dev/null; then
        printf '\033[0;32m  \xe2\x9c\x93 %s installed\033[0m\n' "$name"
      else
        printf '\033[0;33m  \xe2\x86\x92 %s install failed\033[0m\n' "$name"
      fi
    fi
  done << 'EOF'
dlvhdr/gh-dash gh-dash v4.24.1
meiji163/gh-notify gh-notify dff46349970f37c42b1a6fe15e6d62514e848d27
actions/gh-actions-cache gh-actions-cache v1.0.4
EOF
}
