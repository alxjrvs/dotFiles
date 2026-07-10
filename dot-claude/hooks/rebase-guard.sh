#!/usr/bin/env bash
# Claude Code PreToolUse guard — blocks `git push` / `gh pr create` when the
# current branch is behind its target (origin/HEAD), so a spawned agent rebases
# onto the latest target before it publishes. It only checks and blocks; it
# never rewrites history itself (the agent does the rebase, so it resolves
# conflicts with full context and force-with-lease-es on re-push correctly).
#
# Wired agent-side via dot-claude/settings.json `hooks.PreToolUse` (matcher
# "Bash"); this script filters to push/PR-create in-code. It FAILS OPEN (allow)
# on any ambiguity — a productivity guard must never wedge the agent, so a
# missing jq, a non-repo cwd, an unresolvable target, or a parse error all let
# the command through rather than block it.
set -u

allow() { exit 0; }

# Only gate the publish commands; everything else passes untouched. Falls open
# if jq is absent or stdin isn't the expected JSON.
input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2> /dev/null) || allow
case "$cmd" in
  *"git push"* | *"gh pr create"*) : ;;
  *) allow ;;
esac

git rev-parse --is-inside-work-tree > /dev/null 2>&1 || allow

# Resolve the target branch from origin/HEAD; default to origin/main.
target=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2> /dev/null)
target=${target:-origin/main}
branch=${target#origin/}

# Compare against the real remote tip, not a stale local ref.
git fetch --quiet origin "$branch" 2> /dev/null

# Nothing to gate when pushing the target branch itself, or when the target ref
# can't be resolved (e.g. a non-main default with no origin/HEAD set).
[ "$(git symbolic-ref --quiet --short HEAD 2> /dev/null)" = "$branch" ] && allow
git rev-parse --verify --quiet "$target" > /dev/null 2>&1 || allow

# Up to date: the target is an ancestor of HEAD → the branch already contains it.
git merge-base --is-ancestor "$target" HEAD 2> /dev/null && allow

# Behind: block with a rebase instruction the agent acts on.
reason="Branch is behind ${target}. Rebase onto the latest target before pushing: git fetch origin && git rebase ${target} (resolve any conflicts), then re-push with --force-with-lease if the branch was already pushed."
jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0
