#!/usr/bin/env bash
# bootstrap.sh — get a bare machine to a working `dotctl sync` in 4 steps.
#
# After this runs, `dotctl` is on PATH and owns everything else: installs
# Homebrew, mise toolchains, sheldon, gh extensions, fzf, lefthook, claude
# CLI, applies macOS defaults, creates symlinks.
#
# Pre-reqs: git + curl. That's it. Rust is installed by this script.
#
# Usage from a fresh machine:
#   git clone https://github.com/alxjrvs/dotFiles ~/dotFiles
#   ~/dotFiles/bootstrap.sh

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

red() { printf '\033[0;31m%s\033[0m\n' "$*"; }
yellow() { printf '\033[0;33m%s\033[0m\n' "$*"; }
green() { printf '\033[0;32m%s\033[0m\n' "$*"; }

# ── 1. Rust toolchain via rustup ──────────────────────────────────
if ! command -v cargo > /dev/null 2>&1; then
  yellow "==> Installing Rust (rustup)..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs |
    sh -s -- -y --default-toolchain stable --profile minimal --no-modify-path
  # shellcheck disable=SC1091
  . "$HOME/.cargo/env"
  green "  ✓ Rust installed"
else
  green "  ✓ cargo already on PATH"
fi

# ── 2. Build + install dotctl into ~/.local/bin ───────────────────
yellow "==> Building dotctl..."
mkdir -p "$HOME/.local/bin"
cargo install --path "$DOTFILES_DIR/dotctl" --root "$HOME/.local" --force --quiet
export PATH="$HOME/.local/bin:$PATH"
green "  ✓ dotctl installed at $HOME/.local/bin/dotctl"

# ── 3. Hand off to dotctl sync ────────────────────────────────────
yellow "==> Handing off to dotctl sync..."
echo ""
export DOTFILES_DIR
exec "$HOME/.local/bin/dotctl" sync "$@"
