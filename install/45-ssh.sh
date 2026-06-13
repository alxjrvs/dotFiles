#!/usr/bin/env bash
# install/45-ssh.sh — SSH commit-signing convergence via 1Password.
# Tags: ssh
# Sourced by sync; not standalone.
#
# Auth AND signing both go through the 1Password SSH agent. git signs with
# 1Password's op-ssh-sign (gpg.ssh.program) using the "GitHubSSH" key — no
# dedicated signing key, no second ssh-agent. Requires 1Password running with
# the SSH agent enabled (Settings -> Developer).

_ssh_tags() { printf 'ssh\n'; }

# Read the signing key's public line from the 1Password agent and echo just
# "<type> <data>" (no comment). Empty if the agent is down or the key absent.
_ssh_signing_pubkey() {
  [[ -S "$_OP_AGENT_SOCK" ]] || return 0
  local line type data
  line=$(SSH_AUTH_SOCK="$_OP_AGENT_SOCK" ssh-add -L 2> /dev/null | grep " ${_SIGNING_KEY_NAME}\$" | head -1)
  [[ -n "$line" ]] || return 0
  read -r type data _ <<< "$line"
  printf '%s %s\n' "$type" "$data"
}

_ssh_run() {
  printf '\n==> SSH signing (1Password / op-ssh-sign)\n'

  # Config constants, assigned at run time (not module-source time) so sourcing
  # this module has no side effects — consistent with every other install
  # module. Plain (not `local`) so _ssh_signing_pubkey, called below, sees them
  # via bash dynamic scope. Customize the 1Password signing-key item name here:
  _SIGNING_KEY_NAME="GitHubSSH"
  _OP_AGENT_SOCK="${HOME}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
  _OP_SSH_SIGN="/Applications/1Password.app/Contents/MacOS/op-ssh-sign"

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '\033[0;36m  ~ [dry-run] would converge signing in ~/.gitconfig.local + ~/.ssh/allowed_signers\033[0m\n'
    return 0
  fi

  mkdir -p "${HOME}/.ssh"
  chmod 700 "${HOME}/.ssh" 2> /dev/null || true

  if [[ ! -x "$_OP_SSH_SIGN" ]]; then
    printf '\033[0;33m  \xe2\x86\x92 op-ssh-sign not found (install 1Password) — skipping signing setup\033[0m\n'
    return 0
  fi

  local pub
  pub=$(_ssh_signing_pubkey)
  if [[ -z "$pub" ]]; then
    printf '\033[0;33m  \xe2\x86\x92 1Password agent not offering "%s" (running? SSH agent enabled?) — skipping\033[0m\n' "$_SIGNING_KEY_NAME"
    return 0
  fi

  # Machine-local git overrides: sign with the 1Password key via op-ssh-sign.
  # gpgSign stays machine-local so a box without 1Password doesn't fail commits
  # before this has run.
  local cfg="${HOME}/.gitconfig.local"
  [[ -e "$cfg" ]] || printf '# Machine-local git overrides — NOT in dotfiles. Written by dot sync.\n' > "$cfg"
  git config --file "$cfg" commit.gpgSign true
  git config --file "$cfg" tag.gpgSign true
  git config --file "$cfg" gpg.ssh.program "$_OP_SSH_SIGN"
  local want="key::${pub}"
  if [[ "$(git config --file "$cfg" user.signingkey 2> /dev/null || true)" != "$want" ]]; then
    git config --file "$cfg" user.signingkey "$want"
    printf '\033[0;33m  \xe2\x86\x92 signingkey set to the 1Password "%s" key\033[0m\n' "$_SIGNING_KEY_NAME"
  fi

  # allowed_signers (append-only) so `git log --show-signature` verifies.
  local allowed="${HOME}/.ssh/allowed_signers" email
  email=$(git config --file "${DOTFILES_DIR}/.gitconfig" user.email 2> /dev/null || true)
  if [[ -n "$email" ]]; then
    local line="${email} ${pub}"
    if [[ ! -e "$allowed" ]] || ! grep -qxF "$line" "$allowed"; then
      printf '%s\n' "$line" >> "$allowed"
      printf '\033[0;33m  \xe2\x86\x92 allowed_signers updated\033[0m\n'
    fi
    chmod 600 "$allowed"
  fi

  printf '\033[0;32m  \xe2\x9c\x93 SSH signing converged (op-ssh-sign)\033[0m\n'
}
