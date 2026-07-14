#!/usr/bin/env bash
# Claude Code PreToolUse guard — blocks `git checkout <default>` / `git switch
# <default>` from inside a LINKED worktree, where git fails hard with
# "'<default>' is already used by worktree <path>" (exit 128). Agents reflexively
# run `git checkout main && git status && git log` to "check state"; in a worktree
# that crashes every time and burns a recovery turn. This steers them to inspect
# the default branch read-only (`git log origin/<default>`) or stay on their
# branch to do work.
#
# Wired agent-side via dot-claude/settings.json `hooks.PreToolUse` (matcher
# "Bash"), alongside rebase-guard.sh. It FAILS OPEN (allow) on any ambiguity — a
# guard must never wedge the agent: a missing jq, a non-repo cwd, the primary
# worktree (which legitimately owns the branch), or a parse error all pass through.
set -u

allow() { exit 0; }

# Only gate real commands; fall open if jq is absent or stdin isn't the expected
# JSON envelope.
input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2> /dev/null) || allow
[ -n "$cmd" ] || allow

git rev-parse --is-inside-work-tree > /dev/null 2>&1 || allow

# Only inside a *linked* worktree: there, the per-worktree git-dir
# (…/.git/worktrees/<name>) differs from the shared common dir (…/.git). The
# primary worktree — where they match — legitimately holds the default branch, so
# a checkout there is fine and passes untouched.
gitdir=$(git rev-parse --absolute-git-dir 2> /dev/null) || allow
commondir=$(git rev-parse --path-format=absolute --git-common-dir 2> /dev/null) || allow
[ "$gitdir" = "$commondir" ] && allow

# Resolve the default branch name from origin/HEAD; default to main. Escape any
# regex-special chars so a branch like `release/1.0` can't mis-match as an ERE.
def=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2> /dev/null)
def=${def#origin/}
def=${def:-main}
def_re=$(printf '%s' "$def" | sed 's/[^[:alnum:]_-]/\\&/g')

# Deny ONLY a plain branch-switch to the default: `git checkout <def>` /
# `git switch <def>` with NO flags between the verb and the name, terminated by
# end-of-string or a shell separator. Precision beats coverage here — the point is
# to never wedge legit work, so we accept false negatives to kill false positives:
#   - `git` must sit at a command boundary (start, or after ; & | ( ) — NOT after
#     another word), so `echo git checkout main` and `-m "…git checkout main…"`
#     (inside a message/argument) pass through.
#   - no flags are consumed before <def>, so `git checkout --detach main` and
#     `git checkout -b main` pass (both are safe / not the reflex).
#   - the terminator excludes a following token, so `git checkout main -- file`
#     (file restore) and `git checkout main.ts` (a path) pass.
# Known, accepted false negatives (git still crashes, just unguarded): quoted
# `"main"`, `git -C dir checkout main`, and shell aliases.
if printf '%s' "$cmd" | grep -Eq "(^|[;&|()])[[:space:]]*git[[:space:]]+(checkout|switch)[[:space:]]+${def_re}[[:space:]]*(\$|[;&|])"; then
  reason="You're in a linked worktree; \`git checkout ${def}\` / \`git switch ${def}\` fails with \"'${def}' is already used by worktree\". To inspect ${def} read-only, use: git log origin/${def} / git diff origin/${def} (or git switch --detach origin/${def}). To do work, stay on your current branch."
  jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
fi
allow
