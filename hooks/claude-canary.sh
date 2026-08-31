#!/usr/bin/env bash
# `boom verify` step — fail when a Claude Code workaround in this repo may have
# become obsolete.
#
# WHY THIS EXISTS. worktree-freshness.sh is not a feature, it is a workaround for a
# client defect measured against 2.1.237 and recorded in dot-claude/DECISIONS.md:
# the `worktree.baseRef: "fresh"` path cuts from the LOCAL `origin/<default>` ref
# and only refreshes it when .git/FETCH_HEAD is older than 24h (86400000 ms) — a
# cache with no invalidation.
#
# Nothing told us when it is fixed. The client self-updates, so the version that
# measurement describes is replaced silently and repeatedly; a workaround whose bug
# is gone is then dead code that still mutates worktrees, and CLAUDE.md's own rule
# is that a measurement recorded against a tool version "expires unnoticed and
# nothing owns it". This owns it.
#
# WHAT IT ACTUALLY ASSERTS — and what it does not. It greps the installed client
# for the string literals those defects are built out of. Minified identifiers
# change with every build, so literals are the only stable surface; this is
# therefore a MONOTONE signal, not a proof. `FETCH_HEAD` plus `86400000` both
# present does not prove the 24h cache still gates the fetch — but the day
# `FETCH_HEAD` stops appearing in the bundle at all, that code path is gone.
# Treat a failure as "go re-measure", never as "the bug is fixed".
#
# The 24h fetch is DOCUMENTED behavior, so its literals going missing would mean
# the behavior changed rather than a bug closed — still worth knowing, because
# worktree-freshness.sh's ENFORCE layer is redundant either way.
#
# POLARITY, which is the whole design. This check fails when the WORKAROUND looks
# unnecessary, not when it looks needed — the opposite of every other check here.
# Three outcomes:
#
#   client not found          exit 0, one line. A machine that installs Claude Code
#                             somewhere else must not fail a verify run.
#   fingerprints intact       exit 0, silent. The normal case.
#   a fingerprint missing     exit 1, naming which hook is now suspect.
#
# THE ANCHOR IS THE NEGATIVE CONTROL, and it is the reason this can be trusted.
# If the client is ever packaged so its strings cannot be read — compressed,
# encrypted, split — then every fingerprint "disappears" at once and a naive check
# reports all-clear forever while proving nothing. So a string that must exist in
# ANY version that does worktrees at all is checked first, and its absence is
# reported as a broken check rather than as good news. A silently-green canary is
# worse than none: it converts an unknown into a false assurance.
#
# The version is printed, never compared. Pinning a baseline here would recreate
# exactly the rot this exists to catch: the constant goes stale, someone bumps it
# to silence the check, and the assertion is gone. DECISIONS.md holds the version
# the measurements were taken against; this reports what is installed now so a
# re-measure has a target.
set -u

# $1 overrides the client path, which is how the regression suite feeds this
# synthetic bundles. Real invocation passes nothing.
target=${1:-}

if [ -z "$target" ]; then
  # The native installer's stable path; `readlink -f` because it stages every
  # release at its own versions/<ver> and this symlink is the answer it wrote.
  # `claude` is a zsh FUNCTION on this machine (zsh/65-claude.zsh), so
  # `command -v claude` is only meaningful in the non-interactive shell a verify
  # step runs in — hence the symlink first and that as the fallback.
  for c in "$HOME/.local/bin/claude" "$(command -v claude 2> /dev/null || true)"; do
    [ -n "$c" ] || continue
    r=$(readlink -f "$c" 2> /dev/null || printf '%s' "$c")
    [ -f "$r" ] && [ -r "$r" ] && {
      target=$r
      break
    }
  done
fi

if [ -z "$target" ] || [ ! -r "$target" ]; then
  echo "claude-canary: no readable Claude Code client found — skipping (nothing to fingerprint)"
  exit 0
fi

version=$("$target" --version 2> /dev/null | head -1) || version=''
[ -n "$version" ] || version='unknown'

# `strings` where available, else `grep -a`. Not cosmetic: a compiled client is
# one enormous "line", and a line-oriented grep pulls the whole thing into memory
# to answer. Splitting into printable runs first bounds that, and costs nothing
# here because every fingerprint below is a self-contained literal — none of them
# needs two tokens to be adjacent.
if command -v strings > /dev/null 2>&1; then
  extract() { strings -n 6 -- "$1" 2> /dev/null; }
else
  extract() { LC_ALL=C grep -a -o -E '[[:print:]]{6,}' -- "$1" 2> /dev/null; }
fi

text=$(extract "$target")
[ -n "$text" ] || {
  echo "claude-canary: read $target ($version) but extracted no printable strings — the fingerprint method is broken, NOT a fixed client. Re-measure per dot-claude/DECISIONS.md before trusting any worktree hook."
  exit 1
}

has() { printf '%s' "$text" | grep -qF -- "$1"; }

# --- the anchor: present in any version that manages worktrees at all -------
has 'refs/remotes/origin/' || {
  echo "claude-canary: $target ($version) yielded strings but not even 'refs/remotes/origin/' — fingerprinting is no longer valid for this packaging. This is a BROKEN CHECK, not a fixed client; re-measure per dot-claude/DECISIONS.md."
  exit 1
}

rc=0

# --- worktree-freshness.sh's bug -------------------------------------------
missing=''
has 'FETCH_HEAD' || missing="$missing FETCH_HEAD"
has '86400000' || missing="$missing 86400000"
[ -z "$missing" ] || {
  echo "claude-canary: $version no longer contains$missing — the 24h FETCH_HEAD cache that worktree-freshness.sh exists for may be gone. Re-measure (dot-claude/DECISIONS.md, '2026-08-20 — agents were starting from a base up to 24h stale'); if the client now fetches honestly, that hook is deletable."
  rc=1
}

exit "$rc"
