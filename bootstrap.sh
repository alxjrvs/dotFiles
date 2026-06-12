#!/usr/bin/env bash
# bootstrap.sh — get a bare machine to a working `dot sync` in 2 steps.
#
# After this runs, `dot sync` owns everything else: installs Homebrew,
# mise toolchains, sheldon, gh extensions, fzf, lefthook, claude CLI,
# applies macOS defaults, creates symlinks.
#
# Pre-reqs: git + curl. That's it.
#
# Usage from a fresh machine:
#   git clone https://github.com/alxjrvs/dotFiles ~/dotFiles
#   ~/dotFiles/bootstrap.sh

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

red() { printf '\033[0;31m%s\033[0m\n' "$*"; }
yellow() { printf '\033[0;33m%s\033[0m\n' "$*"; }
green() { printf '\033[0;32m%s\033[0m\n' "$*"; }

# ── 1. Ensure ~/.local/bin exists (dot symlink is created by sync) ────
mkdir -p "$HOME/.local/bin"
green "  ✓ ~/.local/bin ready"

# ── 2. Hand off to dot sync ───────────────────────────────────────────
yellow "==> Handing off to dot sync..."
echo ""
export DOTFILES_DIR
exec "$DOTFILES_DIR/dot" sync "$@"
