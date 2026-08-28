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
#
# Portability: written for bash 3.2 (`/bin/bash`). The Brewfile does declare
# bash 5, so the old reason given here ("not in the Brewfile") was wrong; the
# real one is that a hook cannot assume its PATH — launchd and a mid-provision
# machine can both hand it the system bash. No arrays; state is carried in
# scalars and positional params, which is also why the segment list is walked
# twice rather than accumulated.
set -u

allow() { exit 0; }
deny() { # $1 = reason
  jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2> /dev/null) || allow
[ -n "$cmd" ] || allow

# Shared parsing (quote-aware splitting, token normalization) lives beside this
# file so both guards cannot drift apart again. Fail OPEN if it is missing —
# a guard that wedges the agent is worse than one that lets a command through.
# shellcheck source=dot-claude/hooks/guard-lib.sh
. "$(dirname -- "$0")/guard-lib.sh" 2> /dev/null || allow

segs=$(_split "$cmd")

# `git -c alias.X=push X origin main` reached main. The global-flag loop below
# consumes `-c alias.yolo=push` as an ordinary value-taking flag and then reads
# the subcommand as `yolo`, so the command was never recognised as a push at all
# and every refspec check downstream was skipped.
#
# The alias is REFUSED, not resolved. Resolving it would mean shelling out to
# `git config` from inside a PreToolUse hook on every git command -- a cost paid
# by every call to catch a spelling nobody uses by accident. A one-line refusal
# with a message saying to spell the push out is the cheaper correct answer.
if printf '%s' "$cmd" | grep -qE '(^|[[:space:]])(-c|--config)[[:space:]]+alias\.'; then
  deny "\`git -c alias.<name>=<cmd>\` defines a command this guard cannot see through: the flag parser reads the alias name as the subcommand, so a push behind one is never checked against the default branch. Spell the command out instead."
fi

# Interpreter payloads are commands. Expanding them here means `bash -c "git
# push origin main"` is judged by the same refspec logic as a bare push, rather
# than being refused wholesale -- so `bash -c "git push origin feature"` still
# works. See _expand_interpreters in guard-lib.sh for why the pipe case needs
# the whole command and why it cannot reach inside a commit message.
segs=$(_expand_interpreters "$cmd" "$segs")

# --- pass 1: what kind of command is this, and against which repo? -----------
is_push=0
is_prcreate=0
pr_base=''
work_dir='' # a leading `cd <path>` decides which repo the push actually targets
while IFS= read -r seg; do
  [ -n "$seg" ] || continue
  set -f
  # shellcheck disable=SC2046 # intentional word-split: _norm emits space-separated tokens
  set -- $(_norm "$seg")
  set +f
  [ $# -gt 0 ] || continue
  prog=${1##*/}
  # Only a `cd` BEFORE the push can change which repo is pushed. Honouring a
  # trailing one let `git push origin main && cd ..` retarget GIT() at a
  # non-repo, so the guard fell through its own fail-open path.
  if [ "$prog" = cd ] && [ "$is_push" = 0 ] && [ -n "${2:-}" ]; then
    work_dir=$(_unquote "$2")
    case "$work_dir" in
      '~') work_dir=$HOME ;;
      '~'/*) work_dir=$HOME/${work_dir#'~'/} ;;
    esac
    continue
  fi
  [ "$prog" = git ] || [ "$prog" = gh ] || continue
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      # `git -C <path>` names the repo the command acts on exactly as a leading
      # `cd` does, so it has to set work_dir rather than being skipped with the
      # other value-taking flags. Discarding it judged every cross-repo push
      # against the SESSION's cwd repo: a legitimate push blocked by an
      # unrelated checkout's staleness, and — worse — a push to another repo's
      # default branch judged against the wrong default, or waved through
      # entirely when the cwd was not a repo at all.
      #
      # Same "before the push only" doctrine as `cd`: a `-C` on a later segment
      # cannot retarget a push that was already matched.
      -C)
        shift
        if [ $# -gt 0 ] && [ "$is_push" = 0 ]; then
          work_dir=$(_unquote "$1")
          case "$work_dir" in
            '~') work_dir=$HOME ;;
            '~'/*) work_dir=$HOME/${work_dir#'~'/} ;;
          esac
        fi
        [ $# -gt 0 ] && shift
        ;;
      -c | --git-dir | --work-tree | --namespace | --exec-path)
        shift
        [ $# -gt 0 ] && shift
        ;;
      -*) shift ;;
      *) break ;;
    esac
  done
  sub=${1:-}
  [ "$prog" = git ] && [ "$sub" = push ] && is_push=1
  if [ "$prog" = gh ] && [ "$sub" = pr ] && [ "${2:-}" = create ]; then
    is_prcreate=1
    # A stacked PR (`--base <parent>`) must be judged against ITS base, not
    # origin/HEAD — telling the agent to rebase onto the default would flatten
    # the stack that `rebase-prs` deliberately builds.
    while [ $# -gt 0 ]; do
      case "$1" in
        --base)
          shift
          pr_base=$(_unquote "${1:-}")
          ;;
        --base=*) pr_base=$(_unquote "${1#--base=}") ;;
      esac
      shift
    done
  fi
done << EOF
$segs
EOF
[ "$is_push" = 1 ] || [ "$is_prcreate" = 1 ] || allow

# Run every git query against the repo the command actually acts on. Fails open
# when that path isn't a repo — same doctrine as a non-repo session cwd.
GIT() {
  if [ -n "$work_dir" ]; then
    git -C "$work_dir" "$@"
  else
    git "$@"
  fi
}

GIT rev-parse --is-inside-work-tree > /dev/null 2>&1 || allow

# Resolve the target branch: an explicit `--base` wins, else origin/HEAD.
if [ -n "$pr_base" ]; then
  branch=$pr_base
  target=origin/$pr_base
else
  target=$(GIT symbolic-ref --quiet --short refs/remotes/origin/HEAD 2> /dev/null)
  target=${target:-origin/main}
  branch=${target#origin/}
fi
cur_branch=$(GIT symbolic-ref --quiet --short HEAD 2> /dev/null || printf '')

# --- pass 2: direct-push-to-default guard (real pushes only) -----------------
# EVERY push segment is judged, not just the last. `push_seg=$seg` used to
# overwrite, so `git push origin main && git push origin main --dry-run` was
# allowed on the strength of the trailing dry run while the real push ahead of it
# was never examined.
if [ "$is_push" = 1 ]; then
  while IFS= read -r seg; do
    [ -n "$seg" ] || continue
    set -f
    # shellcheck disable=SC2046 # intentional word-split: _norm emits space-separated tokens
    set -- $(_norm "$seg")
    set +f
    [ $# -gt 0 ] || continue
    [ "${1##*/}" = git ] || continue
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
    [ "${1:-}" = push ] || continue
    shift

    # Walk the push arguments as TOKENS. The old code did
    # `pushargs=${push_seg#*push}`, which strips through the first literal
    # "push" anywhere in the segment — `git -c push.default=current push` left
    # ".default=current push" to tokenize, so it never looked like a bare push.
    dry=0
    skipnext=0
    remote_seen=0
    refspecs=''
    # `--all` and `--mirror` name their refs from the local ref namespace rather
    # than from argv, so the refspec analysis below cannot see them. Left to
    # fall through they reach "no refspec → pushes the CURRENT branch", and from
    # a feature branch that reads as safe — while `--all` pushes every local
    # branch INCLUDING the default one, and `--mirror` additionally deletes
    # remote refs that are absent locally. Both were allowed from a feature
    # branch, in the plainest spelling of the one command CLAUDE.md marks
    # irreversible on first attempt.
    all_refs=0
    while [ $# -gt 0 ]; do
      tok=$(_unquote "$1")
      shift
      if [ "$skipnext" = 1 ]; then
        skipnext=0
        continue
      fi
      case "$tok" in
        --dry-run | -n) dry=1 ;;
        # The ref set is not enumerable from argv — see all_refs above.
        --all | --mirror | --tags | --follow-tags) all_refs=1 ;;
        # Options that consume the following token; without this their value
        # would be counted as a positional and shift the refspec analysis.
        -o | --push-option | --receive-pack | --exec | --repo) skipnext=1 ;;
        # Redirections are not refspecs. An operator that stands alone (`>`,
        # `2>`) also consumes the filename token after it.
        *'>'* | *'<'*)
          case "$tok" in
            *'>' | *'<') skipnext=1 ;;
          esac
          ;;
        -*) ;;
        *)
          if [ "$remote_seen" = 0 ]; then
            remote_seen=1
          else
            refspecs="$refspecs $tok"
          fi
          ;;
      esac
    done

    # A dry run never mutates the remote — let it through.
    [ "$dry" = 1 ] && continue

    # `--all`/`--mirror` reach the default branch from any current branch, so
    # they are judged as a push to it regardless of where HEAD sits. Checked
    # before the refspec analysis, which by construction cannot see these refs.
    if [ "$all_refs" = 1 ]; then
      push_to_default=1
      break
    fi

    # No refspec (at most a remote) → this pushes the CURRENT branch.
    if [ -z "$refspecs" ]; then
      [ -n "$cur_branch" ] && [ "$cur_branch" = "$branch" ] && push_to_default=1 && break
      continue
    fi

    # Otherwise every refspec's DESTINATION decides. `+main` (force), `:main`
    # (delete), `HEAD:main`, `refs/heads/main` and a bare `main` all name it.
    for r in $refspecs; do
      r=${r#+}
      case "$r" in
        *:*) dest=${r#*:} ;;
        *) dest=$r ;;
      esac
      dest=${dest#refs/heads/}
      [ "$dest" = HEAD ] && dest=$cur_branch
      if [ -n "$dest" ] && [ "$dest" = "$branch" ]; then
        push_to_default=1
        break
      fi
    done
    [ "${push_to_default:-0}" = 1 ] && break
  done << EOF
$segs
EOF

  [ "${push_to_default:-0}" = 1 ] && deny "Refusing a direct push to the default branch (${branch}). Cut a feature branch and open a PR instead: git switch -c <branch> && git push -u origin <branch> && gh pr create, then land it with gh pr merge --auto --squash. (Run the push from a plain terminal, not Claude, for a genuine emergency bypass.)"
fi

# --- Behind-target rebase guard (push or pr-create) -------------------------
# Compare against the real remote tip, not a stale local ref.
GIT fetch --quiet origin "$branch" 2> /dev/null
GIT rev-parse --verify --quiet "$target" > /dev/null 2>&1 || allow

# Up to date: the target is an ancestor of HEAD → the branch already contains it.
GIT merge-base --is-ancestor "$target" HEAD 2> /dev/null && allow

# Behind: block with a rebase instruction the agent acts on.
deny "Branch is behind ${target}. Rebase onto the latest target before pushing: git fetch origin && git rebase ${target} (resolve any conflicts), then re-push with --force-with-lease if the branch was already pushed."
