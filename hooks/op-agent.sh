#!/usr/bin/env bash
# op-agent — all 1Password-agent machinery in one verb-dispatched CLI.
# Differentiation is by ARGUMENT, never a new file. Every verb has a live
# consumer — no speculative surface (an HTTP MCP `headersHelper`, when one is
# added, formats its Bearer line from `op-agent secret`).
#
#   op-agent secret <op://ref>   read one secret value to stdout via the SA
#                                (the ref is an arg, not a per-service file)
#   op-agent provision           ensure SA vault + keychain token + git PAT
#   op-agent status              report keychain token presence (exit 0/1)
#
# Stays a standalone script because plugin `*_COMMAND` resolvers (e.g. spacebase)
# exec it by path; the botufile drives provision/status via `on apply|verify`.
set -euo pipefail

# Normalize PATH so `op` (brew) resolves even when a plugin resolver execs us
# with a thin PATH — replaces the old hardcoded /opt/homebrew/bin/op. `security`,
# `git`, `scutil` live in /usr/bin and are always present.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

KEYCHAIN="op-claude-agent"
VAULT="${BOTU_vault:-claude-agent}"

# Load the SA token from the login keychain into THIS process only (no biometric,
# headless-safe). Empty/missing → op falls back to desktop auth.
_load_sa() {
  local t
  t="$(security find-generic-password -s "$KEYCHAIN" -w 2> /dev/null || true)"
  [[ -n "$t" ]] && export OP_SERVICE_ACCOUNT_TOKEN="$t"
  return 0
}

# Emit one secret value to stdout (the `op read` contract: value on success,
# nothing + nonzero on failure). A failed read leaves the consumer's var empty,
# which falls through to its own default — never a malformed value.
cmd_secret() {
  local ref="${1:-}"
  command -v op > /dev/null 2>&1 || return 1
  [[ -n "$ref" ]] || {
    echo "op-agent: secret needs an op:// ref" >&2
    return 2
  }
  _load_sa
  op read "$ref" 2> /dev/null
}

cmd_provision() {
  command -v op > /dev/null 2>&1 || {
    echo "op-agent: op not installed"
    return 0
  }
  if security find-generic-password -s "$KEYCHAIN" > /dev/null 2>&1; then
    echo "op-agent: SA token present"
  else
    op vault list > /dev/null 2>&1 || {
      echo "op-agent: op not signed in — run from a terminal"
      return 0
    }
    op vault get "$VAULT" > /dev/null 2>&1 || op vault create "$VAULT" > /dev/null 2>&1 || {
      echo "op-agent: cannot ensure vault $VAULT"
      return 0
    }
    local host sa token
    host="$(scutil --get LocalHostName 2> /dev/null || hostname -s)"
    sa="claude-agent-$host"
    if token="$(op service-account create "$sa" --vault "$VAULT:read_items" --raw 2> /dev/null)" && [[ -n "$token" ]]; then
      security add-generic-password -U -a "$USER" -s "$KEYCHAIN" -w "$token" 2> /dev/null && echo "op-agent: SA $sa created"
    else
      echo "op-agent: SA create failed (needs owner/admin token)"
    fi
  fi
  local pat
  if pat="$(op read "op://$VAULT/Claude Git PAT/credential" 2> /dev/null)" && [[ -n "$pat" ]]; then
    printf 'protocol=https\nhost=github.com\nusername=x-access-token\npassword=%s\n\n' "$pat" |
      git credential-osxkeychain store 2> /dev/null && echo "op-agent: git PAT cached (github.com)"
  else
    echo "op-agent: 'Claude Git PAT' not in $VAULT yet"
  fi
}

cmd_status() {
  if security find-generic-password -s "$KEYCHAIN" > /dev/null 2>&1; then
    echo "op-agent: SA token in keychain ($KEYCHAIN)"
    return 0
  fi
  echo "op-agent: SA token missing — run: op-agent provision" >&2
  return 1
}

case "${1:-}" in
  secret)
    shift
    cmd_secret "$@"
    ;;
  provision) cmd_provision ;;
  status) cmd_status ;;
  *)
    printf 'usage: op-agent <secret op://ref | provision | status>\n' >&2
    exit 2
    ;;
esac
