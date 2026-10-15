#!/bin/bash
# Ubuntu, any host: the Brewfile's CLIs and apps from Ubuntu's archive or the vendor's own signed
# apt repo (never a Snap), zsh as the login shell, and what Claude Code's sandbox and Claude
# desktop's Cowork need. Re-runs when this script changes; installs, never upgrades. MAIA.md lists
# what has no clean Ubuntu route. Each step says what it does first.
set -euo pipefail
say() { printf 'ubuntu: %s\n' "$*"; }
sudo -v

say "curl and gnupg, for the repo keys"
sudo apt-get update -q
sudo apt-get install -y -q ca-certificates curl gnupg

# A vendor repo: its key, then its source file, each written only when absent (a package may
# manage its own afterwards). The key is dearmored when the keyring is a .gpg and its fingerprint
# checked when the vendor publishes one.
repo() {
  local name=$1 key=$2 keyring=$3 source=$4 content=$5 fingerprint=${6:-} tmp
  if [ ! -s "$keyring" ]; then
    say "$name: signing key into $keyring"
    tmp=$(mktemp)
    curl -fsSL "$key" -o "$tmp"
    if [ -n "$fingerprint" ] && ! gpg --show-keys --with-colons "$tmp" | grep -q "^fpr:*$fingerprint:"; then
      rm -f "$tmp"
      echo "ubuntu: $name's key is not $fingerprint; not trusting it" >&2
      return 1
    fi
    sudo install -d -m 0755 "${keyring%/*}"
    if [[ $keyring == *.gpg ]] && ! grep -q 'BEGIN PGP' "$tmp"; then
      sudo install -m 0644 "$tmp" "$keyring"
    elif [[ $keyring == *.gpg ]]; then
      gpg --dearmor < "$tmp" | sudo tee "$keyring" > /dev/null
    else
      sudo install -m 0644 "$tmp" "$keyring"
    fi
    rm -f "$tmp"
  fi
  if [ ! -s "$source" ]; then
    say "$name: apt source $source"
    printf '%s\n' "$content" | sudo tee "$source" > /dev/null
  fi
}

# The commands in each vendor's install docs, as of 2026-10.
# https://code.claude.com/docs/en/setup#install-with-linux-package-managers
repo "Claude Code" https://downloads.claude.ai/keys/claude-code.asc \
  /etc/apt/keyrings/claude-code.asc /etc/apt/sources.list.d/claude-code.list \
  "deb [signed-by=/etc/apt/keyrings/claude-code.asc] https://downloads.claude.ai/claude-code/apt/stable stable main" \
  31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE
# https://code.claude.com/docs/en/desktop-linux
repo "Claude desktop" https://downloads.claude.ai/claude-desktop/key.asc \
  /usr/share/keyrings/claude-desktop-archive-keyring.asc /etc/apt/sources.list.d/claude-desktop.list \
  "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.asc] https://downloads.claude.ai/claude-desktop/apt/stable stable main" \
  31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE
# https://support.1password.com/install-linux/ : the desktop app holds the SSH agent and signs commits.
repo 1Password https://downloads.1password.com/linux/keys/1password.asc \
  /usr/share/keyrings/1password-archive-keyring.gpg /etc/apt/sources.list.d/1password.list \
  "deb [arch=amd64 signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/amd64 stable main"
if [ ! -s /etc/debsig/policies/AC2D62742012EA22/1password.pol ]; then
  say "1Password: debsig policy"
  sudo mkdir -p /etc/debsig/policies/AC2D62742012EA22 /usr/share/debsig/keyrings/AC2D62742012EA22
  curl -fsSL https://downloads.1password.com/linux/debian/debsig/1password.pol |
    sudo tee /etc/debsig/policies/AC2D62742012EA22/1password.pol > /dev/null
  sudo cp /usr/share/keyrings/1password-archive-keyring.gpg /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg
fi
# https://github.com/cli/cli/blob/trunk/docs/install_linux.md
repo "GitHub CLI" https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  /etc/apt/keyrings/githubcli-archive-keyring.gpg /etc/apt/sources.list.d/github-cli.list \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main"
# https://code.visualstudio.com/docs/setup/linux
repo "VS Code" https://packages.microsoft.com/keys/microsoft.asc \
  /usr/share/keyrings/microsoft.gpg /etc/apt/sources.list.d/vscode.sources \
  "Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64,arm64,armhf
Signed-By: /usr/share/keyrings/microsoft.gpg"

# Brewfile → apt: fd is fd-find (~/.local/bin/fd links Debian's fdfind), Fira Code is
# fonts-firacode; git is the archive's, not Xcode's. wl-clipboard and xdg-utils back the zshrc's
# pbcopy, pbpaste and open. bubblewrap and socat are Claude Code's sandbox, which settings.json
# requires; claude-desktop's recommends bring Cowork's QEMU.
say "packages"
sudo apt-get update -q
sudo apt-get install -y \
  zsh git curl jq ripgrep fd-find starship wl-clipboard xdg-utils unzip usbutils fonts-firacode \
  gh 1password 1password-cli code obs-studio \
  claude-code claude-desktop bubblewrap socat

# https://code.claude.com/docs/en/sandboxing: Ubuntu 24.04 and later stop bwrap from making the
# user namespaces it isolates with, unless a profile lets it.
if [ "$(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2> /dev/null || echo 0)" = 1 ] &&
  [ ! -e /etc/apparmor.d/bwrap ]; then
  say "AppArmor: let bwrap make user namespaces, for Claude Code's sandbox"
  sudo tee /etc/apparmor.d/bwrap > /dev/null << 'PROFILE'
abi <abi/4.0>,
include <tunables/global>

profile bwrap /usr/bin/bwrap flags=(unconfined) {
  userns,
  include if exists <local/bwrap>
}
PROFILE
  sudo systemctl reload apparmor
fi

# Cowork's VM talks over vhost-vsock: the module at every boot, as Claude desktop's docs give it.
if [ ! -e /etc/modules-load.d/vhost_vsock.conf ]; then
  say "loading vhost_vsock at boot, for Cowork"
  echo vhost_vsock | sudo tee /etc/modules-load.d/vhost_vsock.conf > /dev/null
fi
sudo modprobe vhost_vsock || say "no vhost_vsock in this kernel; Cowork will say what it lacks"

# Cowork opens /dev/vhost-vsock, which only kvm members can. Groups apply from the next login.
if ! id -nG "$USER" | grep -qw kvm; then
  say "adding $USER to kvm, for Cowork"
  sudo usermod -aG kvm "$USER"
fi

zsh=$(command -v zsh)
if [ "$(getent passwd "$USER" | cut -d: -f7)" != "$zsh" ]; then
  say "login shell: $zsh"
  sudo chsh -s "$zsh" "$USER"
fi
