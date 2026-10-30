#!/bin/bash
# CachyOS: the Brewfile's CLIs and apps from pacman, or the AUR where Arch has no package, zsh as
# the login shell, and what Claude Code's sandbox and Claude desktop's Cowork need. Re-runs when
# this script changes; installs, never upgrades (that is `sudo pacman -Syu`, CachyOS's own).
# Each step says what it does first.
set -euo pipefail
say() { printf 'cachyos: %s\n' "$*"; }
sudo -v

# Brewfile → pacman: gh is github-cli, Fira Code is ttf-fira-code, OrbStack is Docker's own
# engine, and Raycast is Plasma's KRunner (Alt+Space), already there. wl-clipboard and xdg-utils
# back the zshrc's pbcopy, pbpaste and open; bubblewrap and socat are Claude Code's sandbox, which
# settings.json requires. noTunes is the Mac's alone, and Tuple has no Linux build.
say "packages"
sudo pacman -S --needed --noconfirm \
  zsh git curl jq ripgrep fd fzf github-cli starship wl-clipboard xdg-utils unzip ttf-fira-code \
  ghostty code obs-studio discord claude-desktop docker docker-buildx docker-compose \
  bubblewrap socat paru

# The AUR's, built by paru, which asks before it builds anything new.
say "AUR packages"
paru -S --needed 1password 1password-cli google-chrome slack-desktop google-cloud-cli ngrok

# Containers as OrbStack gives them on the Mac: the engine on demand, and docker without sudo. The
# docker group is root on this machine by another name.
say "Docker: the socket, and $USER in docker"
sudo systemctl enable --now docker.socket
if ! id -nG "$USER" | grep -qw docker; then sudo usermod -aG docker "$USER"; fi

# Cowork's VM talks over vhost-vsock, which only kvm members can open: the module at every boot,
# as Claude desktop's docs give it. Groups apply from the next login.
if [ ! -e /etc/modules-load.d/vhost_vsock.conf ]; then
  say "loading vhost_vsock at boot, for Cowork"
  echo vhost_vsock | sudo tee /etc/modules-load.d/vhost_vsock.conf > /dev/null
fi
sudo modprobe vhost_vsock || say "no vhost_vsock in this kernel; Cowork will say what it lacks"
if ! id -nG "$USER" | grep -qw kvm; then
  say "adding $USER to kvm, for Cowork"
  sudo usermod -aG kvm "$USER"
fi

zsh=$(command -v zsh)
if [ "$(getent passwd "$USER" | cut -d: -f7)" != "$zsh" ]; then
  say "login shell: $zsh"
  sudo chsh -s "$zsh" "$USER"
fi
