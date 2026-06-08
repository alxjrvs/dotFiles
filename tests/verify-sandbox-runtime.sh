#!/usr/bin/env bash
# tests/verify-sandbox-runtime.sh — runtime probe of the Claude Code sandbox.
#
# Unlike tests/bats (which asserts settings.json STRUCTURE), this exercises the
# LIVE sandbox by attempting real operations and reporting BLOCKED/ALLOWED vs
# what the hardened config intends. It is only meaningful when run BY CLAUDE
# (i.e. via the sandboxed Bash tool) — run in a plain terminal it is unsandboxed
# and every probe will say ALLOWED. After changing dot-claude/settings.json,
# ask Claude to run:  bash tests/verify-sandbox-runtime.sh
#
# It never prints secret contents — write-probes append nothing / use temp
# names, read-probes check only the errno. Probe files are cleaned up.
set -uo pipefail

pass=0 fail=0
ok() {
  printf '  \033[0;32m✓\033[0m %s\n' "$1"
  pass=$((pass + 1))
}
bad() {
  printf '  \033[0;31m✗\033[0m %s\n' "$1"
  fail=$((fail + 1))
}
note() { printf '  \033[0;33m→\033[0m %s\n' "$1"; }

# can_write PATH -> 0 if a write succeeds, 1 if blocked. Appends nothing.
can_write() {
  python3 - "$1" << 'PY' 2> /dev/null
import sys
try:
    open(sys.argv[1], 'a').close(); print('OK')
except Exception:
    sys.exit(1)
PY
}

printf '\n==> denyWrite (sandboxed writes to credential/exec files must be BLOCKED)\n'
for p in "$HOME/.gitconfig" "$HOME/.config/git/config" "$HOME/.cargo/credentials.toml" \
  "/opt/homebrew/bin/_sbx_probe_$$" "$HOME/.claude/.credentials.json"; do
  if can_write "$p" > /dev/null; then
    bad "writable (should be denied): $p"
    rm -f "$p" 2> /dev/null
  else ok "blocked: $p"; fi
done

printf '\n==> per-repo .git protection (platform default, sandboxed write BLOCKED)\n'
t="$HOME/.cache/_sbx_git_$$"
rm -rf "$t"
if git init -q "$t" 2> /dev/null && [ -f "$t/.git/config" ]; then bad "git init wrote .git under \$HOME (unexpected)"; else ok ".git/hooks|config write blocked under \$HOME"; fi
rm -rf "$t" 2> /dev/null

printf '\n==> allowWrite (legit cache writes must be ALLOWED)\n'
for p in "$HOME/.cache/_sbx_probe_$$" "$HOME/.cargo/registry/_sbx_$$"; do
  mkdir -p "$(dirname "$p")" 2> /dev/null
  if can_write "$p" > /dev/null; then
    ok "writable: $p"
    rm -f "$p" 2> /dev/null
  else bad "blocked (should be allowed): $p"; fi
done

printf '\n==> denyRead (sandboxed read of the gh token must be BLOCKED)\n'
# Only check the errno, never the content. EPERM => sandbox-denied (good).
if python3 -c "open('$HOME/.config/gh/hosts.yml','rb').read(1)" 2> /dev/null; then
  bad "gh hosts.yml is sandbox-readable (token exposed)"
else
  ok "gh hosts.yml read blocked in-sandbox"
fi

printf '\n==> network egress (allowlist)\n'
# http_code 000 = no connection (blocked); any real code = reachable. A proxy
# block also yields 000/timeout, so this distinguishes reachable vs blocked.
http_code() { curl -s -o /dev/null -m 8 -w '%{http_code}' "https://$1" 2> /dev/null; }
gc=$(http_code github.com)
if [ -n "$gc" ] && [ "$gc" != "000" ]; then ok "github.com reachable ($gc, allow-listed)"; else note "github.com unreachable ($gc) — check connectivity"; fi
for d in example.org cloudflare.com httpbin.org; do
  c=$(http_code "$d")
  if [ "$c" = "000" ] || [ -z "$c" ]; then
    ok "$d blocked (not allow-listed)"
  else bad "$d reachable ($c) — egress allowlist is NOT hard (domain-fronting/permissive proxy; documented residual)"; fi
done

printf '\n==> git push prerequisites\n'
auc=$(jq -r '.sandbox.allowUnsandboxedCommands' dot-claude/settings.json 2> /dev/null)
note "allowUnsandboxedCommands = ${auc} (push relies on the unsandboxed retry)"
if gh auth token > /dev/null 2>&1; then
  note "gh token: present in this context"
else
  note "gh token: NOT resolvable here (sandboxed gh can't read hosts.yml — expected; or token invalid → 'gh auth login')"
fi
note "SSH is unusable in-sandbox (no raw TCP); push must be HTTPS via the gh credential helper."

printf '\n==> %d ok, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
