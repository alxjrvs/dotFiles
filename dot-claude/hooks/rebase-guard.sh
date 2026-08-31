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
  # `git -C <path>` names the repo THIS invocation acts on. It is NOT `cd`, and treating the two
  # alike opened a bypass worse than the bug that change fixed:
  #
  #   git -C /tmp status && git push origin main      -> ALLOWED
  #
  # `cd` persists across `&&` segments, so honouring it for the whole command is right. `-C` binds
  # to the single command carrying it, so a `-C` on an EARLIER segment must not retarget a later
  # push. It did: work_dir became /tmp, the is-inside-work-tree probe failed there, and the guard
  # FAILED OPEN on a bare push to the default branch — the one thing CLAUDE.md's first rule exists
  # to stop. Measured against the shipped guard before this change; the three shapes are cases in
  # cases.tsv.
  #
  # So collect per segment into seg_dir and promote it only if this segment turns out to be the
  # push. A `-C` on a non-push segment is then correctly inert.
  seg_dir=''
  while [ $# -gt 0 ]; do
    case "$1" in
      # Discarding -C entirely was the ORIGINAL bug, and it is still a bug: it judged every
      # cross-repo push against the SESSION's cwd repo — a legitimate push blocked by an unrelated
      # checkout's staleness, and worse, a push to another repo's default branch judged against
      # the wrong default. It has to be read; it just must not leak across segments.
      -C)
        shift
        if [ $# -gt 0 ]; then
          d=$(_unquote "$1")
          case "$d" in
            '~') d=$HOME ;;
            '~'/*) d=$HOME/${d#'~'/} ;;
          esac
          # git applies repeated -C cumulatively and resolves a relative one against the cwd it
          # already has — which here is any preceding `cd`. `cd ../foo && git -C bar push` acts on
          # ../foo/bar, and `git -C a -C b` on a/b. Checking ./bar or ./b would land on a
          # nonexistent path and fail open, which is the failure this whole block is about.
          case "$d" in
            /*) seg_dir=$d ;;
            *)
              if [ -n "$seg_dir" ]; then
                seg_dir=$seg_dir/$d
              elif [ -n "$work_dir" ]; then
                seg_dir=$work_dir/$d
              else
                seg_dir=$d
              fi
              ;;
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
  if [ "$prog" = git ] && [ "$sub" = push ]; then
    is_push=1
    # Promote here, and only here: this segment IS the push, so its -C is the repo git will act on.
    [ -n "$seg_dir" ] && work_dir=$seg_dir
  fi
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

# Same, but bounded — for the single network call below. `timeout` cannot wrap a
# shell function, so the two branches are spelled out rather than composed.
GIT_BOUNDED() {
  if command -v timeout > /dev/null 2>&1; then
    if [ -n "$work_dir" ]; then
      timeout 5 git -C "$work_dir" "$@"
    else
      timeout 5 git "$@"
    fi
  else
    GIT "$@"
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
#
# BOUNDED, because this is the one network call in any guard here and it sits in
# front of every push and every `gh pr create`. Measured at ~450 ms on a warm
# network against ~22 ms for the bail-out path — so it is the entire cost of this
# guard, and unbounded it is worse than slow: a hung DNS lookup or an
# unreachable remote would stall the publish path for as long as git waited,
# inside a PreToolUse hook, with the agent simply blocked.
#
# A timed-out fetch is not a failure. The comparison below just runs against the
# last-known `origin/<branch>`; the worst case is a stale ref, which can only make
# this guard MISS a behind-target push, never invent one. Missing is the correct
# direction for a guard that fails open everywhere else.
#
# `timeout` is not in the macOS base system — it arrives with coreutils, which
# the Brewfile declares. Absent, the fetch runs unbounded exactly as before
# rather than being skipped: degrading to the old behaviour beats degrading to
# no check.
# Skipped entirely when the remote-tracking ref is already fresh, which collapses
# a burst of pushes into one round trip. This used to lean on `boom code fetch`
# warming every ~/Code repo on a 15-minute timer; that timer is gone, so the cache
# now hits only behind something that genuinely just fetched — a prior run of this
# guard, worktree-freshness.sh's PREFETCH, or a fetch you ran yourself. Expect the
# ~450 ms path more often than the ~22 ms one. 120 s still catches the case this
# guard is for: a teammate or another agent landing on the target between two
# pushes of your own.
# FETCH_HEAD, not the remote-tracking ref: it is written by every fetch, it
# answers "when did we last talk to origin" directly, and it exists as a real
# file. The ref would have been wrong twice over — `refs/remotes/...` lives in
# the COMMON git dir rather than a worktree's own gitdir, and it may not be a
# loose file at all once refs are packed.
# BOTH git dirs, and the per-worktree one FIRST, because that is where a
# worktree's own fetch lands: measured, `git -C <worktree> fetch` writes
# .git/worktrees/<name>/FETCH_HEAD and leaves the common one untouched. Checking
# only the common dir made this cache never hit from inside a worktree — which
# is where every agent session runs, i.e. it would have been dead code exactly
# where it matters.
fresh=0
for d in "$(GIT rev-parse --git-dir 2> /dev/null || printf '')" \
  "$(GIT rev-parse --git-common-dir 2> /dev/null || printf '')"; do
  [ -n "$d" ] && [ -f "$d/FETCH_HEAD" ] || continue
  # `find -newermt` is the portable mtime comparison; BSD and GNU find both take
  # it. Any failure leaves fresh=0 and the fetch runs, which is the safe way for
  # this to be wrong.
  if [ -n "$(find "$d/FETCH_HEAD" -newermt '-120 seconds' 2> /dev/null)" ]; then
    fresh=1
    break
  fi
done
[ "$fresh" = 1 ] || GIT_BOUNDED fetch --quiet origin "$branch" 2> /dev/null
GIT rev-parse --verify --quiet "$target" > /dev/null 2>&1 || allow

# Up to date: the target is an ancestor of HEAD → the branch already contains it.
GIT merge-base --is-ancestor "$target" HEAD 2> /dev/null && allow

# Behind: block with a rebase instruction the agent acts on.
deny "Branch is behind ${target}. Rebase onto the latest target before pushing: git fetch origin && git rebase ${target} (resolve any conflicts), then re-push with --force-with-lease if the branch was already pushed."
