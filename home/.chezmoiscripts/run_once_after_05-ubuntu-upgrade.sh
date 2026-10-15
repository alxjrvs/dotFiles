#!/bin/bash
# Ubuntu's first apply brings the fresh install current, once: apply never upgrades after this.
# Later upgrades are Ubuntu's own (Software Updater, unattended-upgrades) or `sudo apt full-upgrade`.
set -euo pipefail
echo "ubuntu: apt update and full-upgrade, once"
sudo apt-get update
sudo apt-get full-upgrade -y
