#!/bin/bash
# shellcheck disable=SC2034 # OS/UPGRADE are read by glob-sourced install/*.sh modules
#
# Driver: sources install/lib.sh (shared helpers) then install/*.sh modules
# in numbered order. Each module is independently runnable for surgical
# re-syncs via --only=SECTION.
#
# Layout:
#   install/lib.sh     — helpers (ok/warn/fail/dim, link(), should_run())
#   install/00-brew.sh — Darwin Homebrew + bundle + Tier 3 fallbacks
#   install/05-linux.sh
#   install/10-sheldon-bin.sh
#   install/20-mise.sh — Darwin mise
#   install/30-symlinks.sh
#   install/40-sheldon-plugins.sh
#   install/50-claude.sh
#   install/55-fzf.sh  — Darwin fzf shell integration
#   install/60-gh.sh
#   install/65-git-maint.sh
#   install/70-lefthook.sh
#   install/80-health.sh
#   install/90-macos.sh — Darwin defaults + Caps→Esc + brew doctor

# Globals — read by glob-sourced install/*.sh modules below. SC2034 is
# silenced file-wide because shellcheck only sees sync.sh in isolation.
DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
OS="$(uname -s)" # "Darwin" (macOS) or "Linux" (Raspberry Pi OS)
LINK_MODE=""     # "", "overwrite", or "skip"
ONLY=""          # "", or comma-separated section names
UPGRADE=0        # 1 = run brew update/upgrade/cleanup; 0 = config-only

for arg in "$@"; do
  case "$arg" in
    -f) LINK_MODE="overwrite" ;;
    -s) LINK_MODE="skip" ;;
    --upgrade | -u) UPGRADE=1 ;;
    --only=*)
      ONLY="${arg#--only=}"
      ;;
    -h | --help)
      echo "Usage: $0 [-f] [-s] [-u|--upgrade] [--only=SECTION[,SECTION,...]]"
      echo ""
      echo "Options:"
      echo "  -f              Auto-overwrite conflicts (force)"
      echo "  -s              Auto-skip conflicts"
      echo "  -u, --upgrade   Run brew update + upgrade + cleanup (slow)"
      echo "  --only=SECTION  Only run specified section(s), comma-separated"
      echo ""
      echo "Sections:"
      echo "  brew      Homebrew, Brew Bundle, Brew doctor"
      echo "  mise      mise tool versions"
      echo "  sheldon   Sheldon plugin manager + config"
      echo "  symlinks  All symlinks"
      echo "  claude    Claude Code + config"
      echo "  fzf       fzf shell integration"
      echo "  gh        GitHub CLI + config"
      echo "  nvim      Neovim config"
      echo "  ghostty   Ghostty config"
      echo "  gnar-term gnar-term config (sideproject)"
      echo "  bat       Bat config"
      echo "  atuin     Atuin config"
      echo "  lazygit   Lazygit config"
      echo "  tmux      tmux config"
      echo "  zsh       Zsh fragments (~/.config/zsh/*.zsh)"
      echo "  git       Git config files + maintenance schedule"
      echo "  shell     Shell config (.zshrc, .zprofile)"
      echo "  ssh       ~/.ssh/config symlink"
      echo "  lefthook  Install lefthook hooks for THIS repo"
      echo "  health    Health checks"
      echo "  macos     macOS defaults + Caps→Esc LaunchAgent"
      echo "  linux     Linux system setup"
      exit 0
      ;;
    *)
      printf '\033[0;31m  ✗ %s\033[0m\n' "Unknown option: $arg" >&2
      echo "Usage: $0 [-f] [-s] [--only=SECTION]" >&2
      echo "Run $0 --help for available sections." >&2
      exit 1
      ;;
  esac
done

# ── Cancel on failure or Ctrl-C ──────────────────────────────────
set -eo pipefail

# ── Prevent concurrent runs ────────────────────────────────────
# Use user-private $TMPDIR; atomic noclobber write closes the check-then-set race.
LOCK_FILE="${TMPDIR:-/tmp}/dotfiles-sync.lock"
if [ -f "$LOCK_FILE" ]; then
  lock_pid=$(cat "$LOCK_FILE" 2> /dev/null)
  if kill -0 "$lock_pid" 2> /dev/null; then
    printf '\033[0;31m  ✗ %s\033[0m\n' "Another sync is running (pid $lock_pid)" >&2
    exit 1
  else
    printf '\033[0;33m  → %s\033[0m\n' "Removing stale lock file"
    rm -f "$LOCK_FILE"
  fi
fi
( set -C; echo $$ > "$LOCK_FILE" ) 2> /dev/null || { printf '\033[0;31m  ✗ %s\033[0m\n' "Could not acquire lock" >&2; exit 1; }
trap 'rm -f "$LOCK_FILE"' EXIT
trap 'echo ""; printf "\033[0;31m  ✗ %s\033[0m\n" "Cancelled — stopping install." >&2; exit 1' INT TERM

# ── Source shared helpers + modules ──────────────────────────────
# Order matters: lib first (defines ok/warn/fail/dim/link/should_run used by
# every module); then modules in numbered order. Each module gates itself on
# OS and should_run() — sourcing an inert module is a cheap no-op.

# shellcheck source=install/lib.sh
. "$DOTFILES_DIR/install/lib.sh"

for _mod in "$DOTFILES_DIR"/install/[0-9][0-9]-*.sh; do
  # shellcheck source=/dev/null
  . "$_mod"
done

# ── Summary ────────────────────────────────────────────────────
echo ""
echo "==> Done!"
if [ -z "$ONLY" ]; then
  echo "   Restart your shell or run: source ~/.zshrc"
fi
