#!/usr/bin/env bats
# Unit tests for install/45-ssh.sh (sync-sourced SSH signing convergence).
# CRITICAL: every test runs with HOME inside a bats temp dir. The setup
# guard fails the suite outright if HOME ever resolves to the real home
# (lesson from the fixture leak that wrote user.name=t into the real repo).

ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
ORIG_HOME="$HOME"

setup() {
  TDIR="$(mktemp -d "${TMPDIR:-/tmp}/bats-ssh.XXXXXX")"
  export HOME="$TDIR"
  # Guard: never run against the real home.
  [ "$HOME" != "$ORIG_HOME" ] || exit 1
  export DOTFILES_DIR="$ROOT"
  export __DOT_SYNC_SOURCED=1
  # sync-exported helper the module relies on.
  host_id() { printf 'testhost\n'; }
  export -f host_id
  # shellcheck source=/dev/null
  source "$ROOT/install/45-ssh.sh"
}
teardown() { rm -rf "$TDIR"; }

# ── key generation ───────────────────────────────────────────────────────────

@test "ensure_key: generates ed25519 keypair when absent" {
  run _ssh_ensure_key
  [ "$status" -eq 0 ]
  [ -f "$HOME/.ssh/id_ed25519" ]
  [ -f "$HOME/.ssh/id_ed25519.pub" ]
  run stat -f '%Lp' "$HOME/.ssh/id_ed25519"
  [ "$output" = "600" ]
}

@test "ensure_key: never overwrites an existing key" {
  mkdir -p "$HOME/.ssh"
  echo "sentinel" > "$HOME/.ssh/id_ed25519"
  echo "sentinel-pub" > "$HOME/.ssh/id_ed25519.pub"
  _ssh_ensure_key || true
  [ "$(head -1 "$HOME/.ssh/id_ed25519")" = "sentinel" ]
  [ "$(cat "$HOME/.ssh/id_ed25519.pub")" = "sentinel-pub" ]
}

@test "ensure_key: re-derives missing .pub from existing key" {
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  ssh-keygen -q -t ed25519 -N "" -f "$HOME/.ssh/id_ed25519"
  rm "$HOME/.ssh/id_ed25519.pub"
  run _ssh_ensure_key
  [ "$status" -eq 0 ]
  [ -f "$HOME/.ssh/id_ed25519.pub" ]
  grep -q '^ssh-ed25519 ' "$HOME/.ssh/id_ed25519.pub"
}

# ── gitconfig.local ──────────────────────────────────────────────────────────

@test "gitconfig_local: created with gpgSign + signingkey" {
  mkdir -p "$HOME/.ssh"
  printf 'ssh-ed25519 AAAATESTKEY comment\n' > "$HOME/.ssh/id_ed25519.pub"
  run _ssh_ensure_gitconfig_local
  [ "$status" -eq 0 ]
  [ "$(git config --file "$HOME/.gitconfig.local" commit.gpgSign)" = "true" ]
  [ "$(git config --file "$HOME/.gitconfig.local" tag.gpgSign)" = "true" ]
  [ "$(git config --file "$HOME/.gitconfig.local" user.signingkey)" = "key::ssh-ed25519 AAAATESTKEY comment" ]
}

@test "gitconfig_local: signingkey updated on mismatch, unrelated keys preserved" {
  mkdir -p "$HOME/.ssh"
  printf 'ssh-ed25519 AAAANEWKEY comment\n' > "$HOME/.ssh/id_ed25519.pub"
  git config --file "$HOME/.gitconfig.local" user.signingkey "key::ssh-ed25519 OLDKEY x"
  git config --file "$HOME/.gitconfig.local" maintenance.repo "/some/repo"
  run _ssh_ensure_gitconfig_local
  [ "$(git config --file "$HOME/.gitconfig.local" user.signingkey)" = "key::ssh-ed25519 AAAANEWKEY comment" ]
  [ "$(git config --file "$HOME/.gitconfig.local" maintenance.repo)" = "/some/repo" ]
}

# ── allowed_signers ──────────────────────────────────────────────────────────

@test "allowed_signers: line appended when absent, idempotent, preserves other machines" {
  mkdir -p "$HOME/.ssh"
  printf 'ssh-ed25519 AAAATESTKEY comment\n' > "$HOME/.ssh/id_ed25519.pub"
  printf 'user@example.com ssh-ed25519 OTHERMACHINEKEY pro\n' > "$HOME/.ssh/allowed_signers"
  _ssh_ensure_allowed_signers
  _ssh_ensure_allowed_signers   # idempotency: run twice
  run grep -c 'AAAATESTKEY' "$HOME/.ssh/allowed_signers"
  [ "$output" = "1" ]
  grep -q 'OTHERMACHINEKEY' "$HOME/.ssh/allowed_signers"
}

# ── agent convergence (PATH-shimmed; never touches a real agent) ─────────────

@test "ensure_agent: stale socket removed and agent restarted with -a fixed path" {
  mkdir -p "$HOME/.ssh/agent" "$TDIR/bin"
  ssh-keygen -q -t ed25519 -N "" -f "$HOME/.ssh/id_ed25519"
  touch "$HOME/.ssh/agent/signing.sock"   # stale non-socket file
  cat > "$TDIR/bin/ssh-add" <<'SHIM'
#!/bin/bash
echo "ssh-add $*" >> "$SHIM_LOG"; exit 2
SHIM
  cat > "$TDIR/bin/ssh-agent" <<'SHIM'
#!/bin/bash
echo "ssh-agent $*" >> "$SHIM_LOG"; exit 0
SHIM
  chmod +x "$TDIR/bin/ssh-add" "$TDIR/bin/ssh-agent"
  export SHIM_LOG="$TDIR/shim.log" PATH="$TDIR/bin:$PATH"
  run _ssh_ensure_agent
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.ssh/agent/signing.sock" ]   # stale file removed
  grep -q -- "-a $HOME/.ssh/agent/signing.sock" "$SHIM_LOG"
}
