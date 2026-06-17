#!/usr/bin/env bash
# op-agent — all 1Password-agent machinery in one verb-dispatched CLI.
# Replaces the per-service header shims (gh-mcp-auth-header,
# render-mcp-auth-header — identical but for the ref) and install/47-op-agent.sh.
# Differentiation is by ARGUMENT, never a new file.
#
#   op-agent header <op://ref>   emit {"Authorization":"Bearer …"} for an MCP
#                                headersHelper (the ref is an arg, not a file)
#   op-agent provision           ensure SA vault + keychain token + git PAT
#   op-agent status              report keychain token presence (exit 0/1)
#
# This stays a standalone script ONLY because Claude Code's headersHelper execs
# it by path; the botufile drives provision/status via `on apply|verify op-agent …`.
set -euo pipefail

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

cmd_header() {
  local ref="${1:-${OP_REF:-}}" token
  command -v op > /dev/null 2>&1 || {
    printf '{}\n'
    return 0
  }
  [[ -n "$ref" ]] || {
    printf '{}\n'
    return 0
  }
  _load_sa
  token="$(op read "$ref" 2> /dev/null)" || {
    printf '{}\n'
    return 0
  }
  [[ -n "$token" ]] || {
    printf '{}\n'
    return 0
  }
  printf '{"Authorization":"Bearer %s"}\n' "$token"
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
  header)
    shift
    cmd_header "$@"
    ;;
  provision) cmd_provision ;;
  status) cmd_status ;;
  *)
    printf 'usage: op-agent <header op://ref | provision | status>\n' >&2
    exit 2
    ;;
esac
