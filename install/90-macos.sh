# shellcheck shell=bash
# Darwin: macOS defaults, Caps→Esc LaunchAgent, brew doctor.
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

  # Caps Lock → Escape via hidutil. LaunchAgent re-applies at every login;
  # the inline hidutil call below applies it for the current session.
  mkdir -p "$HOME/Library/LaunchAgents"
  link "$DOTFILES_DIR/macos/LaunchAgents/com.alxjrvs.capsescape.plist" \
    "$HOME/Library/LaunchAgents/com.alxjrvs.capsescape.plist" \
    "LaunchAgents/capsescape.plist"
  if ! launchctl list 2> /dev/null | grep -q com.alxjrvs.capsescape; then
    launchctl load -w "$HOME/Library/LaunchAgents/com.alxjrvs.capsescape.plist" 2> /dev/null || true
  fi
  if hidutil property --set '{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x700000029}]}' > /dev/null 2>&1; then
    ok "Caps Lock → Escape remap active"
  else
    warn "hidutil failed — Caps→Esc not active this session"
  fi
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