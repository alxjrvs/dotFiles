#!/usr/bin/env bash
# install/45-ssh.sh — SSH signing convergence.
# Tags: ssh
# Sourced by sync; not standalone.
#
# Auth keys live in 1Password (ssh/config IdentityAgent). Signing uses a
# dedicated agent at a FIXED socket path — stable across reboots, unlike
# Apple's per-boot-randomized launchd socket.

_ssh_tags() { printf 'ssh\n'; }

_ssh_ensure_dirs() {
  mkdir -p "${HOME}/.ssh/agent"
  chmod 700 "${HOME}/.ssh" "${HOME}/.ssh/agent"
}

# Generate the signing-only keypair if absent; re-derive a missing .pub.
# Never overwrites or rotates an existing key.
_ssh_ensure_key() {
  local key="${HOME}/.ssh/id_ed25519"
  if ! command -v ssh-keygen > /dev/null 2>&1; then
    printf '\033[0;33m  \xe2\x86\x92 ssh-keygen not found — skipping signing key setup\033[0m\n'
    return 0
  fi
  mkdir -p "${HOME}/.ssh"
  chmod 700 "${HOME}/.ssh" 2> /dev/null || true
  if [[ ! -e "$key" ]]; then
    if ssh-keygen -q -t ed25519 -N "" -C "signing-only $(scutil --get LocalHostName 2> /dev/null || hostname -s)" -f "$key"; then
      printf '\033[0;33m  \xe2\x86\x92 generated signing key %s\033[0m\n' "$key"
    else
      printf '\033[0;33m  \xe2\x86\x92 ssh-keygen failed — skipping signing key setup\033[0m\n'
      return 0
    fi
  fi
  chmod 600 "$key" 2> /dev/null || true
  if [[ ! -e "${key}.pub" ]] && [[ -s "$key" ]]; then
    if ssh-keygen -y -f "$key" > "${key}.pub" 2> /dev/null; then
      chmod 644 "${key}.pub"
      printf '\033[0;33m  \xe2\x86\x92 re-derived %s.pub\033[0m\n' "$key"
    else
      rm -f "${key}.pub"
      printf '\033[0;33m  \xe2\x86\x92 could not derive pubkey from %s\033[0m\n' "$key"
    fi
  fi
}

# Dedicated signing agent at a fixed socket path; load the key if absent.
_ssh_ensure_agent() {
  local sock="${HOME}/.ssh/agent/signing.sock"
  local key="${HOME}/.ssh/id_ed25519"
  [[ -f "$key" ]] || return 0
  if ! SSH_AUTH_SOCK="$sock" ssh-add -l > /dev/null 2>&1; then
    rm -f "$sock"
    if ! (umask 077 && ssh-agent -a "$sock" > /dev/null 2>&1); then
      printf '\033[0;33m  \xe2\x86\x92 could not start signing agent at %s\033[0m\n' "$sock"
      return 0
    fi
  fi
  local fp
  fp=$(ssh-keygen -lf "${key}.pub" 2> /dev/null | awk '{print $2}')
  if [[ -n "$fp" ]] && ! SSH_AUTH_SOCK="$sock" ssh-add -l 2> /dev/null | grep -qF "$fp"; then
    # shellcheck disable=SC1007  # DISPLAY= intentionally clears the var for this command
    SSH_AUTH_SOCK="$sock" SSH_ASKPASS_REQUIRE=never SSH_ASKPASS=/usr/bin/false DISPLAY= \
      ssh-add -q "$key" < /dev/null 2> /dev/null ||
      printf '\033[0;33m  \xe2\x86\x92 could not load signing key into agent (passphrase-protected?)\033[0m\n'
  fi
}

# ~/.gitconfig.local: gpgSign on, signingkey = this machine's literal pubkey.
_ssh_ensure_gitconfig_local() {
  local cfg="${HOME}/.gitconfig.local"
  local pub="${HOME}/.ssh/id_ed25519.pub"
  if [[ ! -e "$cfg" ]]; then
    printf '# Machine-local git overrides — NOT in dotfiles. Written by dot sync.\n' > "$cfg"
    printf '\033[0;33m  \xe2\x86\x92 .gitconfig.local bootstrapped\033[0m\n'
  fi
  git config --file "$cfg" commit.gpgSign true
  git config --file "$cfg" tag.gpgSign true
  # Absolute path (machine-local file knows $HOME); pins the agent socket
  # so signing works in sessions that didn't source .zprofile.
  git config --file "$cfg" gpg.ssh.program "${HOME}/.local/bin/git-ssh-sign"
  [[ -f "$pub" ]] || return 0
  local want current
  want="key::$(cat "$pub")"
  current=$(git config --file "$cfg" user.signingkey 2> /dev/null || true)
  if [[ "$current" != "$want" ]]; then
    git config --file "$cfg" user.signingkey "$want"
    printf '\033[0;33m  \xe2\x86\x92 signingkey set to this machine'"'"'s pubkey\033[0m\n'
  fi
}

# allowed_signers: ensure "<email> <pubkey>" line; append-only so every
# machine's key coexists (cross-machine verification).
_ssh_ensure_allowed_signers() {
  local allowed="${HOME}/.ssh/allowed_signers"
  local pub="${HOME}/.ssh/id_ed25519.pub"
  [[ -f "$pub" ]] || return 0
  local email
  email=$(git config --file "${DOTFILES_DIR}/.gitconfig" user.email 2> /dev/null || true)
  if [[ -z "$email" ]]; then
    printf '\033[0;33m  \xe2\x86\x92 no user.email in repo .gitconfig — skipping allowed_signers\033[0m\n'
    return 0
  fi
  local line
  line="$email $(cat "$pub")"
  if [[ ! -e "$allowed" ]] || ! grep -qxF "$line" "$allowed"; then
    printf '%s\n' "$line" >> "$allowed"
    printf '\033[0;33m  \xe2\x86\x92 allowed_signers updated\033[0m\n'
  fi
  chmod 600 "$allowed"
}

_ssh_run() {
  printf '\n==> SSH signing\n'
  _ssh_ensure_dirs
  _ssh_ensure_key
  _ssh_ensure_agent
  _ssh_ensure_gitconfig_local
  _ssh_ensure_allowed_signers
  printf '\033[0;32m  \xe2\x9c\x93 SSH signing converged\033[0m\n'
}
