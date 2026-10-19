#!/bin/bash
# Plasma's counterparts of the macOS defaults. Re-runs only when this script changes; Plasma reads
# the keyboard keys at the next login. kwriteconfig6 sets one key and leaves the rest of the file.
set -euo pipefail

# Caps Lock is Control, as the Mac's capslock LaunchAgent makes it.
kwriteconfig6 --file kxkbrc --group Layout --key Options ctrl:nocaps
kwriteconfig6 --file kxkbrc --group Layout --key ResetOldOptions true

# The Mac's fast repeat: KeyRepeat 2 is 30 ms a key (33 a second), InitialKeyRepeat 15 is 225 ms.
kwriteconfig6 --file kcminputrc --group Keyboard --key RepeatDelay 225
kwriteconfig6 --file kcminputrc --group Keyboard --key RepeatRate 33

# Screenshots into ~/Screenshots (the directory is managed: Screenshots/.keep).
kwriteconfig6 --file spectaclerc --group ImageSave --key imageSaveLocation "file://$HOME/Screenshots"
