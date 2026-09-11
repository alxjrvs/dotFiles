#!/bin/bash
# Homebrew, guarded, every apply: present costs a stat, absent is reinstalled. Mac-only by
# .chezmoiignore. Under NONINTERACTIVE the installer runs `sudo -n` and aborts without a cached
# timestamp, so `sudo -v` takes the one password prompt of the whole bootstrap.
set -euo pipefail
[ -x /opt/homebrew/bin/brew ] && exit 0
sudo -v
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
