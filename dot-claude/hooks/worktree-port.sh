#!/usr/bin/env bash
# Claude Code SessionStart hook — give each agent worktree its own port block, so
# two agents running dev servers do not fight over :3000. Every worktree is a
# full checkout of the same repo and reads the same `PORT ?? 3000`, so the second
# agent gets EADDRINUSE (and reports the feature broken) or — worse, on a
# framework that auto-increments — silently binds :3001 and drives a browser
# against the OTHER worktree's server, which looks like a passing check of code
# that was never loaded.
#
# WHAT IT DOES. Derives a 10-port block from the worktree's own name and announces
# it as `additionalContext`, then makes it real for anything that reads `.env`:
#
#     block = 20000 + (cksum(name) % 1000) * 10      # 20000-29999, 1000 blocks
#
# Blocks, not single ports, because a real app is rarely one listener.
# DERIVED, NOT ALLOCATED, and that is the whole design. A registry of live
# reservations would need a lock, a stale-entry reaper and a place to live; a
# derivation needs none of that and is stable across sessions of the same
# worktree, which is what makes it safe to write into `.env` and safe to print
# twice. `cksum` is POSIX. The cost is birthday collisions — two worktrees of one
# repo share a block roughly 1 in 1000 — which degrades to exactly today's
# behaviour, one EADDRINUSE.
#                                  the user's real file. Asserted directly.
#   - git ignores it             — so the append can never show up as a tracked
#                                  diff and never be committed by an agent.
#   - no PORT is set already     — an explicit `PORT=` is a decision that was
#                                  made on purpose; this must not silently
#                                  override it.
#
# ONLY EVER AN AGENT WORKTREE: a LINKED worktree (git-dir != git-common-dir, both
# resolved with `pwd -P` — the macOS $TMPDIR symlink is how that comparison once
# misread the primary checkout) AND physically under `.claude/worktrees/`. The
# user's own checkout fails both, which is what keeps this hook off their `.env`.
#
# NOT WIRED ON SubagentStart. That event carries the PARENT process cwd, not the
# teammate's worktree, so it could not find the worktree whose port it would be
# assigning. SessionStart fires inside the agent's own session.
#
# FAILS OPEN, always. No jq, no git, a non-repo cwd, a read-only `.env`, a cksum
# that returns something non-numeric — every one exits 0 and says nothing.
set -u

quiet() { exit 0; }

payload=$(cat 2> /dev/null) || payload=''

# cwd from the payload, not $PWD: the payload is the documented contract, $PWD is
# an implementation detail of how the client spawns hooks. Same as the other two.
if command -v jq > /dev/null 2>&1; then
  cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2> /dev/null)
  event=$(printf '%s' "$payload" | jq -r '.hook_event_name // empty' 2> /dev/null)
fi
[ -n "${cwd:-}" ] || cwd=$PWD
[ -n "${event:-}" ] || event=SessionStart

cd "$cwd" 2> /dev/null || quiet
git rev-parse --git-dir > /dev/null 2>&1 || quiet

# --- only ever an agent worktree -------------------------------------------
gd=$(cd "$(git rev-parse --git-dir 2> /dev/null)" 2> /dev/null && pwd -P) || quiet
gcd=$(cd "$(git rev-parse --git-common-dir 2> /dev/null)" 2> /dev/null && pwd -P) || quiet
[ "$gd" != "$gcd" ] || quiet

top=$(git rev-parse --show-toplevel 2> /dev/null) || quiet
top=$(cd "$top" 2> /dev/null && pwd -P) || quiet
parent=$(dirname "$top")
[ "$(basename "$parent")" = worktrees ] || quiet
[ "$(basename "$(dirname "$parent")")" = .claude ] || quiet

# --- derive the block -------------------------------------------------------
name=$(basename "$top")
sum=$(printf '%s' "$name" | cksum 2> /dev/null | awk '{print $1}' 2> /dev/null)
# A non-numeric cksum (absent, or a wrapper printing something else) must not
# become a port expression — arithmetic on it would be a hook crash, not a port.
case ${sum:-} in
  '' | *[!0-9]*) quiet ;;
esac
base=$((20000 + (sum % 1000) * 10))
last=$((base + 9))

# --- make it real where a .env already exists -------------------------------
wrote=''
envf=$top/.env
if [ -f "$envf" ] && [ ! -L "$envf" ] &&
  git check-ignore -q -- "$envf" 2> /dev/null &&
  ! grep -qE '^[[:space:]]*(export[[:space:]]+)?PORT=' "$envf" 2> /dev/null; then
  # Leading newline: a .env with no trailing newline would otherwise get PORT
  # glued onto its last value. Failure to write is not fatal — the context line
  # below still carries the block.
  if printf '\n# worktree-port.sh — this worktree only, never committed\nPORT=%s\n' \
    "$base" >> "$envf" 2> /dev/null; then
    wrote=" PORT=$base was appended to this worktree's .env, so dotenv-reading tools already have it."
  fi
fi

command -v jq > /dev/null 2>&1 || quiet
jq -nc --arg e "$event" --arg c \
  "This worktree's reserved port block is ${base}-${last} (derived from its name, so it is the same every session). Bind dev servers, previews and test fixtures inside that block — starting one on the repo's default port races the other worktrees of this repo, and a framework that auto-increments will quietly serve a DIFFERENT worktree's code.${wrote}" \
  '{hookSpecificOutput:{hookEventName:$e, additionalContext:$c}}' 2> /dev/null

quiet
