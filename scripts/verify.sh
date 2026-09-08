#!/usr/bin/env bash
# Drift check for this machine — the checks that used to be `boom verify` steps, plus chezmoi's
# own. Run by hand, or daily by the com.alxjrvs.dotfiles-verify LaunchAgent with `--notify`,
# which raises a desktop notification on any failure so the exit code does not die in a log.
#
# Exit 0 clean, 1 on any failure. Every check prints one line; failures are prefixed FAIL.
# A check whose tool is absent says so and moves on rather than failing the run — a
# mid-provision machine is not drift.
#
# What is deliberately NOT here: package-version currency (`brew upgrade --formula` and
# `mise upgrade` are each tool's own verb), a shell-startup benchmark, and anything that
# would resolve a secret to check it.
set -uo pipefail

REPO=$(cd -- "$(dirname -- "$0")/.." && pwd)
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:/opt/homebrew/bin:$PATH"

notify=0
[ "${1:-}" = "--notify" ] && notify=1

fail=0
failures=''
ok() { printf 'ok   %s\n' "$1"; }
bad() {
  printf 'FAIL %s\n' "$1"
  failures="$failures
$1"
  fail=1
}
skip() { printf 'skip %s\n' "$1"; }

# ── chezmoi: every managed target matches the source ──────────────────────────
if command -v chezmoi > /dev/null 2>&1; then
  if out=$(chezmoi verify 2>&1); then ok "chezmoi verify"; else bad "chezmoi verify: ${out:-targets differ from source (run: chezmoi apply)}"; fi
else
  skip "chezmoi not installed"
fi

# ── Homebrew: declared is installed, and installed is declared ────────────────
# `brew bundle` never uninstalls what the Brewfile omits, so the second direction is the
# silent one. `brew bundle cleanup` without --force only prints what it would remove
# (formulae, casks, taps; dependencies of declared entries are kept) and exits 0 either way,
# so its output is the finding. A brew copy of a mise-pinned tool is undeclared, so it lands
# in that list too.
brewfile="$HOME/.config/homebrew/Brewfile"
if command -v brew > /dev/null 2>&1 && [ -f "$brewfile" ]; then
  if brew bundle check --no-upgrade --file="$brewfile" > /dev/null 2>&1; then ok "brew bundle check"; else bad "brew bundle check: a declared formula or cask is missing (run: chezmoi apply)"; fi
  out=$(brew bundle cleanup --file="$brewfile" 2>&1)
  if [ -z "$out" ]; then ok "brew bundle cleanup: nothing undeclared"; else bad "brew bundle cleanup would remove (declare it, or brew uninstall it):
$out"; fi
else
  skip "brew or Brewfile absent"
fi

# ── mise: every pinned tool is installed ──────────────────────────────────────
if command -v mise > /dev/null 2>&1; then
  missing=$(mise ls --missing 2> /dev/null | awk 'NF {print $1"@"$2}')
  if [ -z "$missing" ]; then ok "mise tools installed"; else bad "mise tools missing: $(printf '%s' "$missing" | tr '\n' ' ') (run: mise install)"; fi
else
  skip "mise not installed"
fi

# ── gh extensions: the declared list is installed ─────────────────────────────
if command -v gh > /dev/null 2>&1 && [ -f "$REPO/gh-extensions.txt" ]; then
  installed=$(gh extension list 2> /dev/null | awk '{print $3}')
  missing=''
  while IFS= read -r line; do
    ref=$(printf '%s' "${line%%#*}" | tr -d '[:space:]')
    [ -n "$ref" ] || continue
    printf '%s\n' "$installed" | grep -qx "$ref" || missing="$missing $ref"
  done < "$REPO/gh-extensions.txt"
  if [ -z "$missing" ]; then ok "gh extensions"; else bad "gh extensions missing:$missing (run: chezmoi apply)"; fi
else
  skip "gh absent"
fi

# ── Claude Code: the live settings carry the deny floor and every wired hook ──
if [ -f "$HOME/.claude/settings.json" ]; then
  if out=$("$REPO/scripts/settings-guardrails.sh" "$HOME/.claude/settings.json" 2>&1); then ok "settings guardrails (live file)"; else bad "settings guardrails:
$out"; fi
fi

# ── Claude Code: the 1Password MCP server is registered, and no MCP server is dead ──
mcp=/Applications/1Password.app/Contents/MacOS/1password-mcp
if [ -x "$mcp" ] && command -v jq > /dev/null 2>&1; then
  if jq -e '.mcpServers["1password"]' "$HOME/.claude.json" > /dev/null 2>&1; then ok "1Password MCP registered"; else bad "1Password Environments MCP not registered (run: chezmoi apply)"; fi
fi
if command -v claude > /dev/null 2>&1; then
  # Retry before failing: MCP health is flappy (remote 502s, stdio cold starts), and a check
  # that cries wolf trains you to ignore it. Account-level claude.ai connectors are configured
  # at claude.ai, not here, and are filtered out by their display prefix.
  dead=''
  for _ in 1 2 3; do
    dead=$(claude mcp list 2>&1 | grep -v '^claude\.ai ' | grep -E '✘|! Needs authentication' || true)
    [ -n "$dead" ] || break
    sleep 3
  done
  if [ -z "$dead" ]; then ok "MCP servers connect"; else bad "MCP server failing or needs auth (3 checks):
$dead"; fi
fi

# ── op-agent: the service-account token is present, unexpired, and the PAT is live ──
if [ -x "$HOME/.local/bin/op-agent" ]; then
  if out=$(op-agent status 2>&1); then ok "op-agent status"; else bad "op-agent status:
$out"; fi
fi

# ── git maintenance: every registered repo still exists ───────────────────────
# `git config --get-all` without --global, because the keys live in ~/.gitconfig.local via an
# include, and --global does not follow includes.
gone=''
while IFS= read -r r; do
  [ -n "$r" ] || continue
  [ -d "$r" ] || gone="$gone $r"
done <<< "$(git config --get-all maintenance.repo 2> /dev/null)"
if [ -z "$gone" ]; then ok "git maintenance paths"; else bad "git maintenance registered for a missing path:$gone (fix: git maintenance unregister --force <path>)"; fi

# ── launchd: both managed agents are loaded ───────────────────────────────────
if [ "$(uname -s)" = Darwin ]; then
  for label in com.alxjrvs.capslock-control com.alxjrvs.dotfiles-verify; do
    if launchctl print "gui/$(id -u)/$label" > /dev/null 2>&1; then ok "launchd $label"; else bad "launchd $label not loaded (run: chezmoi apply)"; fi
  done
fi

if [ "$fail" -ne 0 ]; then
  if [ "$notify" = 1 ] && command -v osascript > /dev/null 2>&1; then
    n=$(printf '%s' "$failures" | grep -c .)
    osascript -e "display notification \"$n check(s) failed — run scripts/verify.sh\" with title \"dotfiles drift\"" > /dev/null 2>&1 || true
  fi
  exit 1
fi
echo "verify: clean"
