#!/usr/bin/env bash
# Drift check, run by hand when you sit down at a Mac: chezmoi's own verify plus the three
# checks it does not make. Exit 1 on any failure. `--exclude scripts`: verify counts an
# every-apply script as a difference. Upgrades are not drift (`brew upgrade --formula`,
# `mise upgrade`), and nothing here resolves a secret: the keychain check reads metadata only.
#
# FROM A NORMAL TERMINAL, not an agent. Inside Claude Code's Bash sandbox `brew bundle check`
# reports FAIL while printing "The Brewfile's dependencies are satisfied" — it exits nonzero
# because it cannot write its own API cache, not because anything drifted. A drift check that
# cries wolf is worse than none, so do not read a red line from a sandboxed run.
set -uo pipefail
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:/opt/homebrew/bin:$PATH"

fail=0
check() { # $1 = label, $2... = command
  local label=$1 out
  shift
  if out=$("$@" 2>&1); then
    printf 'ok   %s\n' "$label"
  else
    printf 'FAIL %s\n%s\n' "$label" "$out"
    fail=1
  fi
}

check "chezmoi verify" chezmoi verify --exclude scripts
check "brew bundle check" brew bundle check --no-upgrade --file="$HOME/.config/homebrew/Brewfile"
check "op-sa keychain token" security find-generic-password -s op-claude-agent
missing=$(mise ls --missing 2> /dev/null)
if [ -z "$missing" ]; then
  printf 'ok   mise tools installed\n'
else
  printf 'FAIL mise tools missing (run: mise install):\n%s\n' "$missing"
  fail=1
fi

[ "$fail" -eq 0 ] && echo "verify: clean"
exit "$fail"
