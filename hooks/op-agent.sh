#!/usr/bin/env bash
# op-agent — all 1Password-agent machinery in one verb-dispatched CLI.
# Differentiation is by ARGUMENT, never a new file. Every verb has a live
# consumer — no speculative surface.
#
#   op-agent secret <op://ref>   read one secret value to stdout via the SA
#                                (the ref is an arg, not a per-service file)
#   op-agent header <op://ref>   emit {"Authorization":"Bearer …"} for an HTTP
#                                MCP `headersHelper` (GitHub); ref is an arg
#   op-agent git-credential get  git credential helper: resolve the agent PAT
#                                from the vault on demand (same `op` path as
#                                `secret`; git's own `cache` helper amortizes it)
#   op-agent provision           ensure SA vault + keychain token; check git PAT
#   op-agent status              report keychain token presence (exit 0/1)
#
# Stays a standalone script because Claude Code's MCP `headersHelper` and plugin
# `*_COMMAND` resolvers (spacebase, gninety) exec it by path, and git execs it as
# a credential helper; the boomfile drives provision/status via `on apply|verify`.
#
# `header` was deleted on 2026-07-25 alongside the GitHub MCP, its only consumer,
# under this file's rule that every verb has a live consumer — with the explicit
# note to restore it from git history if an HTTP MCP server that bearer-
# authenticates was ever added back. That happened on 2026-07-25: the GitHub MCP
# is reinstalled at api.githubcopilot.com/mcp/ per Claude Code's documented
# `headersHelper` pattern ("a command that writes a JSON object of string
# key-value pairs to stdout"), so the verb is live again rather than speculative.
#
# The server did NOT fail last time because this approach was wrong. It failed
# because the op:// ref contains spaces and was unquoted in the headersHelper
# value: `sh -c` word-split it, this verb hit its failure path and emitted `{}`,
# no Authorization header was sent, and the client fell back to OAuth discovery —
# surfacing as the misleading "does not support dynamic client registration".
# The ref is quoted at the call site now. Keep it quoted.
set -euo pipefail

# Normalize PATH so `op` (brew) resolves even when a plugin resolver execs us
# with a thin PATH — replaces the old hardcoded /opt/homebrew/bin/op. `security`,
# `git`, `scutil` live in /usr/bin and are always present.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

KEYCHAIN="op-claude-agent"
VAULT="${BOOM_vault:-claude-agent}"
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
SA_EXPIRY="${BOOM_sa_expiry:-90d}"
SA_WARN_DAYS="${BOOM_sa_warn_days:-14}"

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

# Emit an MCP `headersHelper` JSON object — {"Authorization":"Bearer <token>"} —
# for an HTTP MCP server that bearer-authenticates (the GitHub MCP at
# api.githubcopilot.com/mcp/). The op:// ref is an argument, not a per-service
# file. On any failure it emits `{}` (valid JSON, no header) so the MCP client
# gets a well-formed response instead of a parse error.
#
# That `{}` failure path is quiet by design, and quiet is exactly how the 2026-07-25
# outage hid: no header went out, the client fell back to OAuth discovery, and the
# only symptom was "does not support dynamic client registration" — an error naming
# neither 1Password nor this script. If the GitHub MCP is ever failing to connect,
# suspect the ref resolving to nothing FIRST. Verify without ever printing the
# token, e.g. compare the output against `{}`:
#   [ "$(op-agent header "op://claude-agent/claude-git-pat/credential")" = '{}' ] \
#     && echo "resolve FAILED" || echo "resolve ok"
cmd_header() {
  local ref="${1:-}" token
  command -v op > /dev/null 2>&1 || {
    printf '{}\n'
    return 0
  }
  [[ -n "$ref" ]] || {
    printf '{}\n'
    return 0
  }
  _load_sa
  token="$(op read "$ref" 2> /dev/null)" && [[ -n "$token" ]] || {
    printf '{}\n'
    return 0
  }
  printf '{"Authorization":"Bearer %s"}\n' "$token"
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
  # is printed, never the token. A 401 = dead → fail (surfaces via `boom verify` +
  # the boom-verify launchd); 403 (rate-limit/SSO) and network/tooling gaps are
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

# audit <manifest> — assert the agent vault contains exactly what the repo says
# it contains, and that every title is kebab-case.
#
# WHY THIS EXISTS. 1Password's own agent guidance leans on two guardrails we do
# not have: the Activity Log and service-account usage reports are Business/Teams
# only, and this is an Individual/Family account. There is therefore NO
# per-item, per-timestamp record of what the SA read — a deliberate, accepted
# gap (2026-08-19). What is left is scope and membership, and SA vault access is
# IMMUTABLE after creation, so scope can never be tightened later. That makes
# vault MEMBERSHIP the only control that stays live, and an unenforced control is
# prose — which this repo distrusts on principle.
#
# So membership becomes declarative: `agent-vault.txt` is the checked-in list of
# what the vault may contain, and drift in EITHER direction fails `boom verify`.
# An item appearing without a commit is exactly the signal the missing audit log
# would have given.
#
# Titles are not secrets, so they may be printed; no field VALUE is ever read.
# Fails closed on drift, advisory on tooling gaps — a broken `op` must never
# wedge verify, the same contract `status` follows.
cmd_audit() {
  local manifest="${1:-}"
  if [[ -z "$manifest" ]]; then
    echo "op-agent: audit needs a manifest path (e.g. agent-vault.txt)" >&2
    return 2
  fi
  if [[ ! -f "$manifest" ]]; then
    echo "op-agent: audit manifest not found: $manifest" >&2
    return 2
  fi
  if ! command -v op > /dev/null 2>&1 || ! command -v jq > /dev/null 2>&1; then
    echo "op-agent: op/jq unavailable — vault audit skipped (advisory)"
    return 0
  fi

  _load_sa
  local actual
  actual="$(op item list --vault "$VAULT" --format=json 2> /dev/null | jq -r '.[].title' 2> /dev/null | LC_ALL=C sort)"
  if [[ -z "$actual" ]]; then
    echo "op-agent: could not list vault ($VAULT), or it is empty — vault audit skipped (advisory)"
    return 0
  fi

  # Comments and blank lines are stripped so the manifest can explain itself.
  local expected
  expected="$(sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$manifest" | LC_ALL=C sort)"

  local rc=0

  # 1. kebab-case. The invariant exists because every op:// ref is re-parsed by
  #    `sh -c`, so a space word-splits and the resolve fails silently. Asserting
  #    the whole shape (not merely "no spaces") keeps refs predictable.
  local bad_titles
  bad_titles="$(printf '%s\n' "$actual" | grep -vE '^[a-z0-9]+(-[a-z0-9]+)*$' || true)"
  if [[ -n "$bad_titles" ]]; then
    echo "op-agent: vault ($VAULT) has non-kebab-case titles — every op:// ref is re-parsed by sh -c:" >&2
    printf '  %s\n' "$bad_titles" >&2
    rc=1
  fi

  # 2. Membership, both directions. An UNDECLARED item is blast radius nobody
  #    reviewed; a MISSING one means a consumer is about to fail.
  local undeclared missing
  undeclared="$(comm -23 <(printf '%s\n' "$actual") <(printf '%s\n' "$expected"))"
  missing="$(comm -13 <(printf '%s\n' "$actual") <(printf '%s\n' "$expected"))"
  if [[ -n "$undeclared" ]]; then
    echo "op-agent: vault ($VAULT) holds items not declared in $manifest:" >&2
    printf '  + %s\n' "$undeclared" >&2
    echo "  Everything here is readable by the service account. Move it out, or declare it." >&2
    rc=1
  fi
  if [[ -n "$missing" ]]; then
    echo "op-agent: $manifest declares items absent from vault ($VAULT):" >&2
    printf '  - %s\n' "$missing" >&2
    rc=1
  fi

  if [[ $rc -eq 0 ]]; then
    echo "op-agent: vault ($VAULT) matches $manifest ($(printf '%s\n' "$actual" | wc -l | tr -d ' ') items)"
  fi
  return $rc
}

case "${1:-}" in
  secret)
    shift
    cmd_secret "$@"
    ;;
  header)
    shift
    cmd_header "$@"
    ;;
  git-credential)
    shift
    cmd_git_credential "$@"
    ;;
  provision) cmd_provision ;;
  status) cmd_status ;;
  audit)
    shift
    cmd_audit "$@"
    ;;
  *)
    printf 'usage: op-agent <secret op://ref | header op://ref | git-credential get | provision | status | audit MANIFEST>\n' >&2
    exit 2
    ;;
esac
