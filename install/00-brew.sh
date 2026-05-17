# shellcheck shell=bash
# Darwin: Homebrew + Brew Bundle + Tier 3 fallbacks.
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

  # ── Tier 3 fallback installs ─────────────────────────────────────
  # Apple Silicon Tahoe (and other Tier 3 configurations) lack pre-built
  # bottles for several formulas the Brewfile lists. Use cargo for rust
  # crates and direct GitHub releases for carapace until upstream bottles
  # arrive. Idempotent — re-runs are no-ops once binaries exist.
  echo ""
  echo "==> Tier 3 fallback installs"

  if command -v cargo &> /dev/null; then
    # Each entry is crate:binary-name (binary differs for watchexec-cli, bottom).
    # --locked respects the crate's pinned dependency graph so transitive yanks
    # don't silently change the build on a fresh box.
    for entry in watchexec-cli:watchexec pueue:pueue bottom:btm git-absorb:git-absorb; do
      crate="${entry%%:*}"
      bin="${entry##*:}"
      if command -v "$bin" &> /dev/null; then
        dim "$bin already installed"
      else
        warn "cargo install $crate (no Tahoe bottle — compiling)..."
        if cargo install --locked "$crate"; then
          ok "$crate installed"
        else
          warn "$crate install failed"
        fi
      fi
    done
  else
    warn "cargo not found — skipping rust fallbacks (run: mise install)"
  fi

  # Carapace: Go binary, also no Tahoe bottle. Pull the latest release from
  # carapace-sh/carapace-bin. Needs jq (in Brewfile).
  if command -v carapace &> /dev/null; then
    dim "carapace already installed ($(carapace --version 2>&1 | head -1))"
  elif command -v jq &> /dev/null; then
    case "$(uname -m)" in
      arm64) _carapace_arch="darwin_arm64" ;;
      x86_64) _carapace_arch="darwin_amd64" ;;
      *) _carapace_arch="" ;;
    esac
    if [ -n "$_carapace_arch" ]; then
      warn "Installing carapace from GitHub releases..."
      mkdir -p "$HOME/.local/bin"
      _tmp=$(mktemp -d)
      _url=$(curl -fsSL "https://api.github.com/repos/carapace-sh/carapace-bin/releases/latest" |
        jq -r --arg pat "$_carapace_arch" '.assets[] | select(.name | test($pat) and test("tar.gz$")) | .browser_download_url' |
        head -1)
      if [ -n "$_url" ] &&
        curl -fsSL "$_url" -o "$_tmp/carapace.tar.gz" &&
        tar xzf "$_tmp/carapace.tar.gz" -C "$_tmp" &&
        mv "$_tmp/carapace" "$HOME/.local/bin/carapace" &&
        chmod +x "$HOME/.local/bin/carapace"; then
        ok "carapace installed at ~/.local/bin/carapace"
      else
        warn "carapace install failed"
      fi
      rm -rf "$_tmp"
    else
      warn "carapace skipped (unsupported arch: $(uname -m))"
    fi
  else
    warn "carapace skipped (jq not installed)"
  fi
fi # should_run brew