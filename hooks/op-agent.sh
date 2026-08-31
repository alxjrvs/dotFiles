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
# Stays a standalone script because Claude Code's MCP `headersHelper` and plugin
# `*_COMMAND` resolvers (spacebase, gninety) exec it by path, and git execs it as
# a credential helper; the boomfile drives provision/status via `on apply|verify`.
#
# `header` is deleted, for the second and final time. It emitted a bearer token
# for an HTTP MCP `headersHelper`, was cut on 2026-07-25 when the GitHub MCP went
# away, and was restored days later when that server came back — then the server
# went away again and the verb did not. On 2026-08-28 an audit found it dispatched
# but unreachable: nothing in the repo declares an HTTP MCP server, and
# `dot-claude/SETTINGS.md` now says outright "Do not re-add
# api.githubcopilot.com/mcp/ behind a bespoke headersHelper".
#
# It is the verb that printed a live PAT into a transcript on 2026-07-25, so a
# dispatchable-but-unused spelling of it is the worst kind of speculative surface.
# Restoring it is `git log -S cmd_header` — but read that SETTINGS.md line first,
# because the last two restorations both preceded the consumer disappearing again.
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
# printf with a multi-line string as a QUOTED argument prints the format once and
# lets the embedded newlines through, so only the first line got its bullet and
# the remaining twelve came out flush-left. Measured on the first real drift
# report, 2026-08-19. Reading line by line keeps titles with spaces intact, which
# word-splitting would not.
_prefixed() { # $1 = prefix; lines on stdin
  local _l
  while IFS= read -r _l; do
    [[ -n "$_l" ]] && printf '%s%s\n' "$1" "$_l"
  done
  return 0
}

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
  # Comments and blank lines are stripped so the manifest can explain itself.
  local expected
  expected="$(sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$manifest" | LC_ALL=C sort)"

  local rc=0

  # 0. Every declared item must be RESOLVED by something in this repo. Deliberately
  #    FIRST and above the op/jq guard: this is a repo-integrity check, so it must
  #    still run on a machine with no `op`, where the vault half is skipped.
  #
  #    The manifest's own rule is that an entry earns its place by having a named
  #    consumer — and that rule was prose until now. `render-api-key` sat in the
  #    vault naming a `render` MCP server that existed in no scope, and passed this
  #    audit every time, because membership and casing were all that was checked.
  #    An agent-readable vault IS the blast radius, and SA vault access is immutable
  #    after creation, so membership is the only lever there is; an orphan widens it
  #    for nothing.
  #
  #    A MENTION is not a consumer, so this looks for an `op://` RESOLUTION ref and
  #    excludes three things that mention items without resolving them: the manifest
  #    itself, DECISIONS.md (history, which discusses items precisely because they
  #    were removed), and the guard fixtures under tests/ (which name arbitrary
  #    items to assert a DENY, so a fixture would vouch for anything).
  #
  #    The VAULT segment allows `$VAULT`/`${BOOM_vault}` and not just a literal, because
  #    that is how this very file spells every ref it resolves: `PAT_REF="op://$VAULT/
  #    claude-git-pat/credential"`. A pattern anchored on a lowercase literal cannot see
  #    its own consumer, and on 2026-08-29 that produced a false orphan — deleting the
  #    retired `header` verb removed the last COMMENT that happened to spell the vault
  #    out longhand, and `claude-git-pat` was reported unconsumed while git's credential
  #    helper was still resolving it on every push. The item segment stays a strict
  #    literal: that is the half being matched against the manifest, and a variable there
  #    would vouch for anything.
  local root refs orphans=""
  root="$(cd -- "$(dirname -- "$manifest")" && pwd)"
  # shellcheck disable=SC2016 # the `$` is a literal to MATCH, not an expansion: refs are
  # spelled `op://$VAULT/item/field` in this file, so the pattern has to contain a real `$`.
  refs="$(grep -rho 'op://[A-Za-z0-9${}_-]*/[a-z0-9-]*' "$root" \
    --exclude="$(basename -- "$manifest")" \
    --exclude=DECISIONS.md \
    --exclude-dir=.git \
    --exclude-dir=tests \
    2> /dev/null | sed 's|.*/||' | LC_ALL=C sort -u)"
  while IFS= read -r item; do
    [[ -n "$item" ]] || continue
    printf '%s\n' "$refs" | grep -qxF "$item" || orphans="$orphans $item"
  done <<< "$expected"
  if [[ -n "$orphans" ]]; then
    echo "op-agent: $manifest declares items nothing in this repo resolves:$orphans" >&2
    echo "  An entry earns its place by having a named consumer. Remove it, or add the consumer." >&2
    rc=1
  fi

  if ! command -v op > /dev/null 2>&1 || ! command -v jq > /dev/null 2>&1; then
    echo "op-agent: op/jq unavailable — vault half of the audit skipped (advisory)"
    return $rc
  fi

  _load_sa
  local actual
  actual="$(op item list --vault "$VAULT" --format=json 2> /dev/null | jq -r '.[].title' 2> /dev/null | LC_ALL=C sort)"
  if [[ -z "$actual" ]]; then
    echo "op-agent: could not list vault ($VAULT), or it is empty — vault half skipped (advisory)"
    return $rc
  fi

  # 1. kebab-case, for DECLARED items only. The invariant exists because every
  #    op:// ref is re-parsed by `sh -c`, so a space word-splits and the resolve
  #    fails silently — which is a property of items this repo RESOLVES, not of
  #    everything that happens to sit in the vault. An item nobody references can
  #    be called whatever 1Password's new-item dialog called it.
  local bad_titles
  bad_titles="$(printf '%s\n' "$expected" | grep -vE '^[a-z0-9]+(-[a-z0-9]+)*$' || true)"
  if [[ -n "$bad_titles" ]]; then
    echo "op-agent: $manifest declares non-kebab-case titles — every op:// ref is re-parsed by sh -c:" >&2
    printf '%s\n' "$bad_titles" | _prefixed '  ' >&2
    rc=1
  fi

  # 2. Membership, both directions. An UNDECLARED item is blast radius nobody
  #    reviewed; a MISSING one means a consumer is about to fail.
  #
  #    LC_ALL=C ON `comm`, NOT ONLY ON `sort`. Both inputs are C-sorted above, and
  #    `comm` requires its inputs to be sorted IN ITS OWN COLLATION. Left ambient
  #    (en_US.UTF-8 here), `comm` uses a locale where case is folded, so `Name`
  #    collates between `gninety` and `npm-publish-token` while the C-sorted input
  #    puts it first. BSD `comm` on macOS does not warn about misordered input the
  #    way GNU does — it silently emits nonsense.
  #
  #    Measured with the real vault contents (Name, claude-git-pat, gninety,
  #    npm-publish-token) against a manifest of the latter three: the unpinned form
  #    reported `claude-git-pat` and `gninety` as BOTH undeclared and missing, which
  #    is impossible, and reported nothing at all about the one item that actually
  #    was undeclared. The whole membership control — the reason this file exists,
  #    since service-account vault scope is immutable and membership is the only
  #    lever — was silently wrong for any capitalized title.
  #    ONE DIRECTION, deliberately. An item in the vault that this manifest does not
  #    name used to fail here, on the reasoning that anything the service account can
  #    read is blast radius somebody should have reviewed. That is a policy, and it
  #    made the vault read-only in practice: adding or retiring a credential failed
  #    `boom verify` until the manifest was edited in the same breath. The vault is a
  #    place to keep things, so putting something in it is not drift.
  #
  #    What remains is the half that predicts a BREAKAGE rather than expressing a
  #    preference: a declared item missing from the vault means a consumer named in
  #    this repo is about to resolve nothing. That is still a failure.
  local missing
  missing="$(LC_ALL=C comm -13 <(printf '%s\n' "$actual") <(printf '%s\n' "$expected"))"
  if [[ -n "$missing" ]]; then
    echo "op-agent: $manifest declares items absent from vault ($VAULT):" >&2
    printf '%s\n' "$missing" | _prefixed '  - ' >&2
    rc=1
  fi

  if [[ $rc -eq 0 ]]; then
    echo "op-agent: every item $manifest declares is present in vault ($VAULT) ($(printf '%s\n' "$expected" | wc -l | tr -d ' ') declared)"
  fi
  return $rc
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
  audit)
    shift
    cmd_audit "$@"
    ;;
  *)
    printf 'usage: op-agent <secret op://ref | git-credential get | provision | status | audit MANIFEST>\n' >&2
    exit 2
    ;;
esac
