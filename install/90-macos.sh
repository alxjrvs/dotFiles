# shellcheck shell=bash
# Darwin: macOS defaults + brew doctor.
# Caps→Esc is handled by Karabiner-Elements (Brewfile cask), not hidutil.
# Brew doctor lives here (not 00-brew.sh) so it runs at the very end —
# preserves the original sync.sh ordering where doctor was last.

[ "$OS" = "Darwin" ] || return 0

if should_run macos; then
  echo ""
  echo "==> macOS defaults"
  # Fast key repeat (essential for vim keybindings)
  defaults write NSGlobalDomain KeyRepeat -int 2
  defaults write NSGlobalDomain InitialKeyRepeat -int 15
  # Disable press-and-hold for keys (enables key repeat everywhere)
  defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
  # Show hidden files in Finder
  defaults write com.apple.finder AppleShowAllFiles -bool true
  # Show file extensions
  defaults write NSGlobalDomain AppleShowAllExtensions -bool true
  # Tap to click on trackpad
  defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
  # Dock settings
  defaults write com.apple.dock autohide -bool true
  defaults write com.apple.dock autohide-delay -float 0
  defaults write com.apple.dock autohide-time-modifier -float 0.3
  defaults write com.apple.dock tilesize -int 48
  # Disable global autocorrect / capitalize / period substitution.
  defaults write -g NSAutomaticSpellingCorrectionEnabled -bool false
  defaults write -g NSAutomaticCapitalizationEnabled -bool false
  defaults write -g NSAutomaticPeriodSubstitutionEnabled -bool false
  defaults write -g NSAutomaticDashSubstitutionEnabled -bool false
  defaults write -g NSAutomaticQuoteSubstitutionEnabled -bool false
  # Screenshots → ~/Screenshots.
  mkdir -p "$HOME/Screenshots"
  defaults write com.apple.screencapture location -string "$HOME/Screenshots"
  killall SystemUIServer 2> /dev/null || true
  # Suppress .DS_Store on network and USB volumes.
  defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
  defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true
  # Show full POSIX path in Finder window title.
  defaults write com.apple.finder _FXShowPosixPathInWindowTitle -bool true
  # Apply Dock and Finder changes
  killall Dock 2> /dev/null || true
  killall Finder 2> /dev/null || true
  ok "macOS defaults applied (Dock and Finder restarted)"
fi # should_run macos

# ── Brew doctor ────────────────────────────────────────────────
if should_run brew; then
  echo ""
  echo "==> Brew doctor"
  if brew doctor 2>&1 | grep -q "ready to brew"; then
    ok "brew doctor: all good"
  else
    warn "brew doctor found issues — run 'brew doctor' for details"
  fi
fi # should_run brew
