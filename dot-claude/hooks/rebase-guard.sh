#!/usr/bin/env bash
# Claude Code PreToolUse guard for `git push` / `gh pr create`. Two jobs:
#   1. Deny a direct push of the default branch (work lands via a feature branch
#      + PR + `gh pr merge --auto`, never a push onto the shared default).
#   2. Deny a push/PR-create when the current branch is BEHIND its target
#      (origin/HEAD), so the agent rebases onto the latest target first.
# It only checks and blocks; it never rewrites history itself (the agent does the
# rebase, resolving conflicts with full context, and force-with-lease-es on
# re-push).
#
# Wired agent-side via dot-claude/settings.json `hooks.PreToolUse` (matcher
# "Bash"). It detects the publish commands by TOKENIZING each simple command (not
# a substring scan), so `git log --grep "git push"` and `echo git push` pass
# untouched. It FAILS OPEN (allow) on any ambiguity — a guard must never wedge the
# agent: a missing jq, a non-repo cwd, an unresolvable target, or a parse error
# all let the command through.
set -u

allow() { exit 0; }
deny() { # $1 = reason
  jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2> /dev/null) || allow
[ -n "$cmd" ] || allow

# Detect a REAL `git push` / `gh pr create` — the subcommand, not a substring.
# Split on shell separators and, for each simple command, skip leading global
# options (and the arg of `-c`/`-C`/etc.) to find the actual subcommand.
is_push=0
is_prcreate=0
segs=$(printf '%s' "$cmd" | sed -E 's/(\|\||&&|[;&|])/\n/g')
while IFS= read -r seg; do
  seg="${seg#"${seg%%[![:space:]]*}"}" # strip leading whitespace
  [ -n "$seg" ] || continue
  set -f
  # shellcheck disable=SC2086 # intentional word-split of one shell segment
  set -- $seg
  set +f
  prog=${1:-}
  [ "$prog" = git ] || [ "$prog" = gh ] || continue
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      -c | -C | --git-dir | --work-tree | --namespace | --exec-path)
        shift
        [ $# -gt 0 ] && shift
        ;;
      -*) shift ;;
      *) break ;;
    esac
  done
  sub=${1:-}
  [ "$prog" = git ] && [ "$sub" = push ] && is_push=1
  [ "$prog" = gh ] && [ "$sub" = pr ] && [ "${2:-}" = create ] && is_prcreate=1
done << EOF
$segs
EOF
[ "$is_push" = 1 ] || [ "$is_prcreate" = 1 ] || allow

git rev-parse --is-inside-work-tree > /dev/null 2>&1 || allow

# Resolve the target branch from origin/HEAD; default to origin/main.
target=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2> /dev/null)
target=${target:-origin/main}
branch=${target#origin/}
def_re=$(printf '%s' "$branch" | sed 's/[^[:alnum:]_-]/\\&/g')

# --- Direct-push-to-default guard (real pushes only) ------------------------
if [ "$is_push" = 1 ]; then
  # A dry run never mutates the remote — let it through entirely.
  case " $cmd " in
    *" --dry-run "*) allow ;;
  esac

  push_to_default=0
  # Explicit destination is the default branch, from ANY current branch:
  #   git push <remote> <def>            git push <remote> <src>:<def>
  #   git push <remote> HEAD:<def>       (a single positional is the REMOTE, not
  # a dest, so `git push main` is NOT matched here).
  printf '%s' "$cmd" |
    grep -Eq "push([[:space:]]+-[^[:space:]]+)*[[:space:]]+[^[:space:]]+[[:space:]]+([^[:space:]]*:)?${def_re}([[:space:]]|\$|[;&|])" &&
    push_to_default=1

  # Bare push (no refspec — at most a remote, otherwise only flags) while HEAD is
  # the default branch → it pushes the default. Tokenize just the push args.
  if [ "$push_to_default" = 0 ] && [ "$(git symbolic-ref --quiet --short HEAD 2> /dev/null)" = "$branch" ]; then
    pushargs=${cmd#*push}
    pushargs=${pushargs%%[;&|]*}
    set -f
    positionals=0
    hascolon=0
    # shellcheck disable=SC2086 # intentional word-split of the push args
    for tok in $pushargs; do
      case "$tok" in
        -*) ;;
        *:*)
          hascolon=1
          positionals=$((positionals + 1))
          ;;
        *) positionals=$((positionals + 1)) ;;
      esac
    done
    set +f
    [ "$hascolon" = 0 ] && [ "$positionals" -le 1 ] && push_to_default=1
  fi

  [ "$push_to_default" = 1 ] && deny "Refusing a direct push to the default branch (${branch}). Cut a feature branch and open a PR instead: git switch -c <branch> && git push -u origin <branch> && gh pr create, then land it with gh pr merge --auto --squash. (Run the push from a plain terminal, not Claude, for a genuine emergency bypass.)"
fi

# --- Behind-target rebase guard (push or pr-create) -------------------------
# Compare against the real remote tip, not a stale local ref.
git fetch --quiet origin "$branch" 2> /dev/null
git rev-parse --verify --quiet "$target" > /dev/null 2>&1 || allow

# Up to date: the target is an ancestor of HEAD → the branch already contains it.
git merge-base --is-ancestor "$target" HEAD 2> /dev/null && allow

# Behind: block with a rebase instruction the agent acts on.
deny "Branch is behind ${target}. Rebase onto the latest target before pushing: git fetch origin && git rebase ${target} (resolve any conflicts), then re-push with --force-with-lease if the branch was already pushed."
