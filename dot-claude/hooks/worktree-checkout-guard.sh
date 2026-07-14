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

# Resolve the default branch name from origin/HEAD; default to main.
def=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2> /dev/null)
def=${def#origin/}
def=${def:-main}

# Match `git checkout <def>` / `git switch <def>` (optionally with leading flags),
# terminated by whitespace, end, or a shell separator so `main.ts` (a path) and
# `origin/main` (a detaching ref, which is safe) don't trip it.
if printf '%s' "$cmd" | grep -Eq "git[[:space:]]+(checkout|switch)[[:space:]]+(-[[:alnum:]-]+[[:space:]]+)*${def}([[:space:]]|\$|&|;|\|)"; then
  reason="You're in a linked worktree; \`git checkout ${def}\` / \`git switch ${def}\` fails with \"'${def}' is already used by worktree\". To inspect ${def} read-only, use: git log origin/${def} / git diff origin/${def} (or git switch --detach origin/${def}). To do work, stay on your current branch."
  jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
fi
allow
