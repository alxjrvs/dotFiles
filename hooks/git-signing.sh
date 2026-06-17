#!/usr/bin/env bash
# hook: git-signing — converge git commit/tag signing via 1Password op-ssh-sign.
# Ported from the old install/45-ssh.sh. Writes machine-local ~/.gitconfig.local
# (gpgSign + signingkey + op-ssh-sign program) and appends ~/.ssh/allowed_signers,
# using the 1Password-agent key named by $BOTU_key (default GitHubSSH). gpgSign
# stays machine-local so a box without 1Password doesn't fail commits.

_git_signing_keyname() { printf '%s' "${BOTU_key:-GitHubSSH}"; }
_GIT_SIGNING_SOCK="${HOME}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
_GIT_SIGNING_PROG="/Applications/1Password.app/Contents/MacOS/op-ssh-sign"

# Echo "<type> <data>" of the signing key from the 1Password agent (empty if down).
_git_signing_pubkey() {
  [[ -S "$_GIT_SIGNING_SOCK" ]] || return 0
  local name line type data
  name="$(_git_signing_keyname)"
  line="$(SSH_AUTH_SOCK="$_GIT_SIGNING_SOCK" ssh-add -L 2> /dev/null | grep " ${name}\$" | head -1)"
  [[ -n "$line" ]] || return 0
  read -r type data _ <<< "$line"
  printf '%s %s\n' "$type" "$data"
}

_git_signing_apply() {
  _hdr "git signing (1Password / op-ssh-sign)"
  local name
  name="$(_git_signing_keyname)"
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    _note "would converge signing in ~/.gitconfig.local + ~/.ssh/allowed_signers"
    return 0
  fi
  [[ -x "$_GIT_SIGNING_PROG" ]] || {
    _warn "op-ssh-sign not found (install 1Password) — skipping signing setup"
    return 0
  }
  local pub
  pub="$(_git_signing_pubkey)"
  [[ -n "$pub" ]] || {
    _warn "1Password agent not offering \"$name\" (running? SSH agent enabled?) — skipping"
    return 0
  }

  # Machine-local git overrides: sign with the 1Password key via op-ssh-sign.
  local cfg="$HOME/.gitconfig.local"
  [[ -e "$cfg" ]] || printf '# Machine-local git overrides — NOT in dotfiles. Written by botu.\n' > "$cfg"
  git config --file "$cfg" commit.gpgSign true
  git config --file "$cfg" tag.gpgSign true
  git config --file "$cfg" gpg.ssh.program "$_GIT_SIGNING_PROG"
  local want="key::${pub}"
  if [[ "$(git config --file "$cfg" user.signingkey 2> /dev/null || true)" != "$want" ]]; then
    git config --file "$cfg" user.signingkey "$want"
    _ok "signingkey set to the 1Password \"$name\" key"
  fi

  # allowed_signers (append-only) so `git log --show-signature` verifies locally.
  local allowed="$HOME/.ssh/allowed_signers" email
  email="$(git config --file "$BOTU_CONFIG/.gitconfig" user.email 2> /dev/null || true)"
  if [[ -n "$email" ]]; then
    local line="${email} ${pub}"
    if [[ ! -e "$allowed" ]] || ! grep -qxF "$line" "$allowed"; then
      printf '%s\n' "$line" >> "$allowed"
      _ok "allowed_signers updated"
    fi
    chmod 600 "$allowed"
  fi
  _ok "signing converged (op-ssh-sign)"
}

_git_signing_verify() {
  _hdr "git signing"
  if [[ "$(git config --file "$HOME/.gitconfig.local" commit.gpgSign 2> /dev/null || true)" == "true" ]]; then
    _ok "commit signing enabled (~/.gitconfig.local)"
  else
    _warn "signing not configured — run: botu apply --only=git-signing"
  fi
}

_git_signing_fix() { _git_signing_apply; }
