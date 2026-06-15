#!/usr/bin/env bash
# install/47-op-agent.sh — provision the agent's 1Password service account and
# cache the agent git PAT for the sandbox.
# Tags: op-agent
# Sourced by sync; not standalone.
#
# The hands-off agent (Claude / MCP / cron) resolves secrets through a 1Password
# *service account*, never your biometric desktop session — so a Claude session,
# interactive or headless, gets its secrets with no Touch ID prompt and no
# desktop-app dependency. This module converges, idempotently:
#   1. a dedicated `claude-agent` vault — 1Password FORBIDS granting a service
#      account access to Personal/Private, so agent secrets must live apart;
#   2. a per-host service account with read_items on only that vault;
#   3. its token in the macOS login keychain (service `op-claude-agent`);
#   4. the fine-grained git PAT cached into the login keychain as the github.com
#      credential, so a SANDBOXED Claude session can auth git-over-HTTPS via the
#      stock `osxkeychain` helper (op can't run in-box — see _op_agent_cache_git_pat).
# The MCP headersHelper shims (gh/gh-mcp-auth-header, render/render-mcp-auth-header)
# read the keychain token inline. Foreground only: minting the account authorizes
# through the 1Password desktop app, which needs the calling session.
#
# Idempotent: the SA setup is a no-op once the keychain token exists; the git PAT
# cache refreshes every run (so PAT rotation = re-sync). To rotate the SA, delete
# it in the 1Password web UI AND remove the keychain item, then re-run:
#   security delete-generic-password -s op-claude-agent
#   dot sync --only=op-agent

_op_agent_tags() { printf 'op-agent\n'; }

_OP_AGENT_VAULT="claude-agent"
_OP_AGENT_KEYCHAIN_SERVICE="op-claude-agent"

_op_agent_run() {
  printf '\n==> 1Password agent service account\n'

  if ! command -v op > /dev/null 2>&1; then
    printf '\033[0;33m  \xe2\x86\x92 op (1Password CLI) not installed — skipping\033[0m\n'
    return 0
  fi

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '\033[0;36m  ~ [dry-run] would ensure "%s" vault + per-host service account + keychain token, and cache the git PAT for in-box osxkeychain auth\033[0m\n' "$_OP_AGENT_VAULT"
    return 0
  fi

  _op_agent_ensure_sa
  _op_agent_cache_git_pat
}

# Vault + per-host service account + keychain token. Idempotent on the keychain
# token (no-op + no unlock prompt once present).
_op_agent_ensure_sa() {
  if security find-generic-password -s "$_OP_AGENT_KEYCHAIN_SERVICE" > /dev/null 2>&1; then
    printf '\033[0;32m  \xe2\x9c\x93 service-account token present in keychain\033[0m\n'
    return 0
  fi

  # First-time bootstrap needs an unlocked, signed-in op session (foreground).
  if ! op vault list > /dev/null 2>&1; then
    printf '\033[0;33m  \xe2\x86\x92 op not signed in / locked — skip; run "dot sync --only=op-agent" from a regular terminal\033[0m\n' >&2
    return 0
  fi

  # 1. Ensure the dedicated vault.
  if op vault get "$_OP_AGENT_VAULT" > /dev/null 2>&1; then
    printf '\033[0;32m  \xe2\x9c\x93 vault "%s" exists\033[0m\n' "$_OP_AGENT_VAULT"
  elif op vault create "$_OP_AGENT_VAULT" > /dev/null 2>&1; then
    printf '\033[0;33m  \xe2\x86\x92 vault "%s" created\033[0m\n' "$_OP_AGENT_VAULT"
  else
    printf '\033[0;33m  \xe2\x86\x92 could not create vault "%s" (service accounts need a Business/Teams account) — skipping\033[0m\n' "$_OP_AGENT_VAULT" >&2
    return 0
  fi

  # 2 + 3. Mint a per-host service account scoped to that vault and store the
  # token straight into the login keychain. --raw emits only the token; it is
  # captured into a variable and handed to `security`, never echoed or written
  # to disk. (The token is briefly visible to `ps` on the security argv — an
  # accepted single-user-laptop tradeoff.)
  local host sa_name token
  host=$(scutil --get LocalHostName 2> /dev/null || hostname -s)
  sa_name="claude-agent-${host}"
  if token=$(op service-account create "$sa_name" --vault "${_OP_AGENT_VAULT}:read_items" --raw 2> /dev/null) && [[ -n "$token" ]]; then
    if security add-generic-password -U -a "$USER" -s "$_OP_AGENT_KEYCHAIN_SERVICE" -w "$token" 2> /dev/null; then
      printf '\033[0;32m  \xe2\x9c\x93 service account "%s" created; token stored in keychain (%s)\033[0m\n' "$sa_name" "$_OP_AGENT_KEYCHAIN_SERVICE"
    else
      printf '\033[0;31m  \xe2\x9c\x97 token minted but keychain store failed — store it: security add-generic-password -U -a "%s" -s %s -w <token>\033[0m\n' "$USER" "$_OP_AGENT_KEYCHAIN_SERVICE" >&2
    fi
  else
    printf '\033[0;33m  \xe2\x86\x92 service-account create failed (account owner/admin token required, name taken, or unsupported plan) — skipping\033[0m\n' >&2
  fi

  # The agent secrets themselves (GitHub PAT, Render key) must live in this vault
  # — the service account cannot read Personal/Private.
  printf '\033[0;36m  ~ next: move agent secrets into the "%s" vault (op item move "<item>" --destination-vault %s)\033[0m\n' "$_OP_AGENT_VAULT" "$_OP_AGENT_VAULT"
}

# Cache the fine-grained git PAT into the macOS login keychain so a SANDBOXED
# Claude session can authenticate git-over-HTTPS via the stock `osxkeychain`
# helper. `op` itself can't run inside Claude Code's bash sandbox (its TLS is
# MITM'd by the sandbox proxy → errSecNotTrusted), but keychain *reads* work
# in-box — so we resolve the PAT HERE (sync runs unsandboxed, keychain writes
# allowed) and the agent only reads it later. Refreshes every run → rotation =
# re-sync. No-op (with a hint) until the PAT is minted into the vault.
_op_agent_cache_git_pat() {
  local pat
  if pat=$(op read "op://${_OP_AGENT_VAULT}/Claude Git PAT/credential" 2> /dev/null) && [[ -n "$pat" ]]; then
    if printf 'protocol=https\nhost=github.com\nusername=x-access-token\npassword=%s\n\n' "$pat" |
      git credential-osxkeychain store 2> /dev/null; then
      printf '\033[0;32m  \xe2\x9c\x93 git PAT cached in login keychain (github.com) for in-box osxkeychain auth\033[0m\n'
    fi
  else
    printf '\033[0;33m  \xe2\x86\x92 "Claude Git PAT" not in %s yet — sandboxed-agent git-over-HTTPS will fail until you mint it (op item create --category "API Credential" --title "Claude Git PAT" --vault %s credential=<pat>)\033[0m\n' "$_OP_AGENT_VAULT" "$_OP_AGENT_VAULT" >&2
  fi
}
