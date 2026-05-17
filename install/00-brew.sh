# shellcheck shell=bash
# Darwin: Homebrew + Brew Bundle.
# CLI tools without Tier 3 bottles (carapace/watchexec/pueue/bottom/git-absorb)
# now install via mise (see mise.toml + install/20-mise.sh).
# Brew doctor lives in 90-macos.sh so it runs at the very end (preserves
# the original sync.sh ordering — health-style checks last).

[ "$OS" = "Darwin" ] || return 0

if should_run brew; then
  echo ""
  echo "==> Homebrew"
  if command -v brew &> /dev/null; then
    ok "Homebrew installed"
  else
    warn "Installing Homebrew..."
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi

  if ((UPGRADE)); then
    warn "Updating Homebrew..."
    brew update

    warn "Upgrading formulae and casks..."
    brew upgrade
    brew upgrade --cask

    warn "Removing outdated versions..."
    brew cleanup --prune=all
  else
    dim "Skipping brew update/upgrade/cleanup (pass --upgrade to run)"
  fi

  # ── Brew Bundle ──────────────────────────────────────────────────
  echo ""
  echo "==> Brew Bundle"

  # Check for Xcode Command Line Tools (required by Homebrew)
  if ! xcode-select --version &> /dev/null 2>&1; then
    warn "Installing Xcode Command Line Tools..."
    xcode-select --install
    fail "Xcode CLT installer opened — approve the dialog, then re-run sync.sh"
    exit 1
  fi

  warn "Installing Brewfile dependencies (skipping upgrades)..."
  brew bundle --file="$DOTFILES_DIR/Brewfile" --no-upgrade
  ok "Brewfile dependencies up to date"

  # Docker Desktop provides its own docker CLI — remove the formula if both exist
  if brew list --cask docker-desktop &> /dev/null && brew list --formula docker &> /dev/null; then
    warn "Removing docker formula (conflicts with Docker Desktop)..."
    brew uninstall --formula docker
    brew uninstall --formula docker-completion 2> /dev/null || true
    ok "docker formula removed — Docker Desktop provides the CLI"
  fi
fi # should_run brew
