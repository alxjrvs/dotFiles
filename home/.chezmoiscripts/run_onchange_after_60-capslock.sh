#!/bin/bash
# Caps Lock → Control with the OS's own remapper, no kernel extension and no approval dialog.
# Mac-only by .chezmoiignore; re-runs when this file changes. Apple TN2450 usage IDs: 0x39 caps
# lock, 0xE0 left control. A hidutil mapping does not survive a reboot, so a launchd agent
# re-applies it at login; the plist is written here rather than managed, so chezmoi never sets a
# mode on ~/Library. bootout first so a changed plist is re-read; RunAtLoad applies it now.
set -euo pipefail
label=com.alxjrvs.capslock
agent="$HOME/Library/LaunchAgents/$label.plist"
mkdir -p "$(dirname "$agent")"
cat > "$agent" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.alxjrvs.capslock</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/hidutil</string>
    <string>property</string>
    <string>--set</string>
    <string>{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x7000000E0}]}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
EOF
launchctl bootout "gui/$(id -u)/$label" 2> /dev/null || true
launchctl bootstrap "gui/$(id -u)" "$agent"
