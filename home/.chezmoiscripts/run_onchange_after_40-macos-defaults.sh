#!/bin/bash
# macOS defaults. Re-runs only when this script changes (its own content is the hash), then
# restarts the apps that read these keys at launch.
set -euo pipefail

# Keyboard: fast repeat, no press-and-hold accent popover.
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false

# Finder: everything visible, POSIX path in the title. `_FXShowPosixPathInTitle` is the key
# Finder reads; it was misspelled `…InWindowTitle` for years and read as converged while doing
# nothing.
defaults write com.apple.finder AppleShowAllFiles -bool true
defaults write NSGlobalDomain AppleShowAllExtensions -bool true
defaults write com.apple.finder _FXShowPosixPathInTitle -bool true

# Trackpad tap-to-click; Dock hidden with no delay.
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock autohide-time-modifier -float 0.3

# No automatic text substitution anywhere a terminal or editor might inherit it.
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false

# No .DS_Store on network or USB volumes.
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

# Screenshots into ~/Screenshots (the directory is managed: Screenshots/.keep).
defaults write com.apple.screencapture location -string "$HOME/Screenshots"

killall Dock Finder SystemUIServer 2> /dev/null || true
