#!/bin/bash
# Homebrew, once, so a fresh Mac is chezmoi's one line. Mac-only by .chezmoiignore. The installer
# still asks sudo for a password; NONINTERACTIVE skips its "press RETURN" only.
set -euo pipefail
[ -x /opt/homebrew/bin/brew ] || NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
