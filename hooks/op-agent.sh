#!/usr/bin/env bash
# op-agent — all 1Password-agent machinery in one verb-dispatched CLI.
# Differentiation is by ARGUMENT, never a new file. Every verb has a live
# consumer — no speculative surface.
#
#   op-agent secret <op://ref>   read one secret value to stdout via the SA
#                                (the ref is an arg, not a per-service file)
#   op-agent git-credential get  git credential helper: resolve the agent PAT
#                                from the vault on demand (same `op` path as
#                                `secret`; git's own `cache` helper amortizes it)
#   op-agent provision           ensure SA vault + keychain token; check git PAT
#   op-agent status              report keychain token presence (exit 0/1)
#
# Stays a standalone script because Claude Code's plugin `*_COMMAND` resolver
# (gninety) execs it by path, and git execs it as a credential helper; the
# boomfile drives provision/status via `on = "sync"` / `on = "verify"`.
#
# `header` is deleted. It emitted a bearer token for an HTTP MCP `headersHelper`; nothing in
# the repo declares an HTTP MCP server, and it is the verb that printed a live PAT into a
# transcript on 2026-07-25. Do not re-add api.githubcopilot.com/mcp/ behind a bespoke
# headersHelper. Restoring it is `git log -S cmd_header`.

set -euo pipefail

# Normalize PATH so `op` (brew) resolves even when a plugin resolver execs us
# with a thin PATH — replaces the old hardcoded /opt/homebrew/bin/op. `security`,
# `git`, `scutil` live in /usr/bin and are always present.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

KEYCHAIN="op-claude-agent"
VAULT="claude-agent"
# Item titles in this vault are kept space-free on purpose. Every consumer of an
# op:// ref runs it through `sh -c` (MCP `headersHelper`, plugin `*_COMMAND`), so
# a title with spaces word-splits into separate arguments unless every call site
# quotes it — a silent failure that took down two MCP servers on 2026-07-25.
# Renamed 'Claude Git PAT' → 'claude-git-pat' so quoting stops being load-bearing.
PAT_REF="op://$VAULT/claude-git-pat/credential"
# Lifetime for a NEWLY minted service-account token, and the warn threshold for an
# existing one. 90d is a deliberate pick, not a vendor default: 1Password documents
# no rotation cadence and no default/maximum for --expires-in. Long enough not to be
# busywork on a machine that reprovisions rarely, short enough that a leaked token
# has a horizon. Rotation is manual (web UI only), so the warning window has to be
# wide enough to act on.
SA_EXPIRY="90d"
SA_WARN_DAYS=14

# Load the SA token from the login keychain into THIS process only (no biometric,
# headless-safe). Empty/missing → op falls back to desktop auth.
_load_sa() {
  local t
  t="$(security find-generic-password -s "$KEYCHAIN" -w 2> /dev/null || true)"
  [[ -n "$t" ]] && export OP_SERVICE_ACCOUNT_TOKEN="$t"
  return 0
}

# Print the SA token's `exp` claim (unix epoch) to stdout, or fail silently.
#
# 1Password provides NO way to see when a service-account token expires: there is
# no `op service-account list`/`get`, no expiry field in the UI's token view, and
# no pre-expiry email or Watchtower alert. So when a token does lapse, every agent
# secret resolve starts failing at once with no warning — the same failure shape as
# the PAT probe below, which is why it lives in the same place.
#
# The tokens are JWTs behind an `ops_` scanner prefix, so the claim is readable
# locally: no network, no extra 1Password call, no vault convention to maintain.
# It reads the token already in this process's env and prints ONLY the epoch —
# never the token, never any other claim. Any malformed/unexpected shape fails
# closed to "unknown", which the caller treats as advisory rather than guessing.
_sa_expiry_epoch() {
  local tok payload exp
  tok="${OP_SERVICE_ACCOUNT_TOKEN:-}"
  [[ -n "$tok" ]] || return 1
  command -v jq > /dev/null 2>&1 || return 1

  tok="${tok#ops_}"
  payload="$(printf '%s' "$tok" | cut -d. -f2)"
  [[ -n "$payload" ]] || return 1

  # base64url -> base64, then re-pad to a multiple of 4.
  payload="${payload//-/+}"
  payload="${payload//_//}"
  case $((${#payload} % 4)) in
    2) payload="$payload==" ;;
    3) payload="$payload=" ;;
    1) return 1 ;;
  esac

  # macOS shipped `-D` long before `-d`; try both rather than assume a version.
  exp="$(printf '%s' "$payload" | { base64 -d 2> /dev/null || base64 -D 2> /dev/null; } |
    jq -r '.exp // empty' 2> /dev/null)" || return 1
  [[ "$exp" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$exp"
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

# git credential helper, scoped to https://github.com in the agent git config.
# On `get` it resolves the agent PAT from the vault via the SA — the same on-demand
# `op` path as `secret`, so the PAT lives only in 1Password (no keychain cache).
# git's built-in `cache` helper sits in front to amortize the round-trip. `store`
# and `erase` are no-ops: the vault is the source of truth, not git. A failed read
# emits nothing (git falls through), never a malformed credential.
cmd_git_credential() {
  [[ "${1:-}" == get ]] || return 0
  command -v op > /dev/null 2>&1 || return 0
  _load_sa
  local pat
  pat="$(op read "$PAT_REF" 2> /dev/null)" && [[ -n "$pat" ]] || return 0
  printf 'username=x-access-token\npassword=%s\n' "$pat"
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
    # --expires-in is CREATE-time only. 1Password's "Rotate Token" issues a new
    # token but keeps the existing permissions and offers no way to add an expiry,
    # and there is no CLI/API for it at all (`op service-account` has exactly two
    # subcommands, `create` and `ratelimit`). So a long-lived SA can only gain an
    # expiry by being REPLACED, and this flag only takes effect on a fresh
    # provision — a new machine, or after deliberately deleting the keychain item
    # and the old service account. Without it the token is open-ended, which is
    # what the docs' "SA-scoped vault plus a token expiry" was resting on while no
    # code passed the flag.
    if token="$(op service-account create "$sa" --vault "$VAULT:read_items" --expires-in "$SA_EXPIRY" --raw 2> /dev/null)" && [[ -n "$token" ]]; then
      security add-generic-password -U -a "$USER" -s "$KEYCHAIN" -w "$token" 2> /dev/null && echo "op-agent: SA $sa created"
    else
      echo "op-agent: SA create failed (needs owner/admin token)"
    fi
  fi
  # Resolve the PAT via the SA token (from the keychain), NOT desktop auth. Without
  # this, the bare `op read` below falls back to biometric and re-prompts Touch ID on
  # EVERY `boom source`. The SA can read the claude-agent vault where the PAT lives, so
  # this is headless. On a first-ever provision the token was just created above, so
  # _load_sa picks it up too; only SA *creation* itself needs the one-time biometric.
  _load_sa
  # The PAT is resolved on demand by `git-credential` (no keychain cache); just
  # confirm the vault item exists so a fresh machine gets a clear setup signal.
  if op read "$PAT_REF" > /dev/null 2>&1; then
    echo "op-agent: git PAT present in vault ($VAULT)"
  else
    echo "op-agent: 'claude-git-pat' not in $VAULT yet"
  fi
}

cmd_status() {
  security find-generic-password -s "$KEYCHAIN" > /dev/null 2>&1 || {
    echo "op-agent: SA token missing — run: op-agent provision" >&2
    return 1
  }
  echo "op-agent: SA token in keychain ($KEYCHAIN)"

  # SA token expiry. Checked before the PAT probe because it needs no network and
  # no `op`: a lapsed SA token breaks every secret path at once, including the PAT
  # resolve below, so reporting "PAT not resolvable" first would be a symptom
  # masking its own cause. Expired fails verify (like the PAT's 401); an unreadable
  # or absent claim is silent, since an open-ended token is the pre-2026-08-05
  # normal and not itself a fault.
  _load_sa
  local sa_exp sa_days sa_now sa_ago
  if sa_exp="$(_sa_expiry_epoch)"; then
    sa_now=$(date +%s)
    # Compare EPOCHS, not a day count. `(exp - now) / 86400` truncates toward
    # zero, so for the first 24h after the token lapsed sa_days was 0 — which is
    # not `-lt 0`, so this fell through to the warn branch, printed the
    # reassuring "expires in 0d" and returned 0. `boom verify` therefore stayed
    # green for a full day after every agent secret path was already dead.
    if [[ $sa_exp -le $sa_now ]]; then
      sa_ago=$((sa_now - sa_exp))
      if [[ $sa_ago -lt 86400 ]]; then
        echo "op-agent: SA token EXPIRED (<1d ago) — mint a new service account and re-run: op-agent provision" >&2
      else
        echo "op-agent: SA token EXPIRED $((sa_ago / 86400))d ago — mint a new service account and re-run: op-agent provision" >&2
      fi
      return 1
    fi
    sa_days=$(((sa_exp - sa_now) / 86400))
    # Always state the expiry, not only when it is close. Silence used to be
    # ambiguous in exactly the wrong direction: no line meant EITHER ">14 days
    # left" OR "this token never expires", and those are opposite security
    # postures. On 2026-08-19 an audit could not tell them apart from the output,
    # and there is no other source of truth — 1Password exposes no expiry API and
    # shows no expiry field in the token UI, so the local `exp` claim is it.
    if [[ $sa_days -le $SA_WARN_DAYS ]]; then
      echo "op-agent: SA token expires in ${sa_days}d ($(date -r "$sa_exp" +%Y-%m-%d)) — rotation is 1Password web UI only (no CLI/API)"
    else
      echo "op-agent: SA token expires $(date -r "$sa_exp" +%Y-%m-%d) (${sa_days}d)"
    fi
  else
    # Not a failure — an open-ended token is the pre-2026-08-05 normal and
    # breaks nothing. But it is no longer silent, because it means one of the two
    # legs least privilege rests on is simply absent. Scope is immutable and
    # (with auditing declined on this plan) unauditable, so expiry is the only
    # remaining time bound, and `provision` short-circuits once a keychain token
    # exists — an SA minted before --expires-in existed can never acquire one.
    # Only a REPLACEMENT service account gains an expiry: 1Password's "Rotate
    # Token" keeps the permissions and offers no expiry option.
    echo "op-agent: SA token is OPEN-ENDED (no exp claim) — scope + expiry are the only least-privilege legs here and this one is missing; only a replacement service account can gain one"
  fi

  # PAT liveness. The agent's git PAT is a classic token with an expiry: when it
  # lapses, git-credential silently returns a dead token and every agent push then
  # fails with no warning. Probe it here — the one place that already handles the
  # PAT, so the boomfile/launchd stay clean and the token never touches a tracked
  # file or the model's context. Resolve via the SA and hit the API; only OK/expiry
  # is printed, never the token. A 401 = dead → fail (surfaces on the next `boom
  # verify`, which is now run by hand); 403 (rate-limit/SSO) and network/tooling gaps are
  # advisory so a flaky connection or throttle never fails verify.
  command -v op > /dev/null 2>&1 && command -v curl > /dev/null 2>&1 || return 0
  _load_sa
  local pat code
  pat="$(op read "$PAT_REF" 2> /dev/null)" || {
    echo "op-agent: git PAT not resolvable from vault ($VAULT) — advisory"
    return 0
  }
  [[ -n "$pat" ]] || {
    echo "op-agent: git PAT empty in vault ($VAULT) — advisory"
    return 0
  }
  # Keep the PAT off curl's argv (visible via `ps`): feed the auth header through
  # a `-K -` config on stdin, so the token stays inside this process like every
  # other op-agent secret path.
  code="$(printf 'header = "Authorization: token %s"\n' "$pat" |
    curl -s -o /dev/null -w '%{http_code}' -m 8 -K - https://api.github.com/user 2> /dev/null || echo 000)"
  case "$code" in
    200) echo "op-agent: git PAT live" ;;
    # 401 is unambiguous "bad/expired credential" → dead. 403 is NOT: GitHub also
    # returns it for secondary-rate-limit and SSO-enforcement on an otherwise live
    # token, so treat it as advisory rather than failing verify on a false alarm.
    401)
      echo "op-agent: git PAT DEAD/expired (HTTP 401) — rotate 'claude-git-pat' in vault $VAULT" >&2
      return 1
      ;;
    *) echo "op-agent: git PAT liveness unknown (HTTP $code) — network/rate-limit/SSO, not failing" ;;
  esac
  return 0
}

case "${1:-}" in
  secret)
    shift
    cmd_secret "$@"
    ;;
  git-credential)
    shift
    cmd_git_credential "$@"
    ;;
  provision) cmd_provision ;;
  status) cmd_status ;;
  *)
    printf 'usage: op-agent <secret op://ref | git-credential get | provision | status>\n' >&2
    exit 2
    ;;
esac
