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

# Shared parsing (quote-aware splitting, token normalization) lives beside this
# file so both guards cannot drift apart again. Fail OPEN if it is missing.
# shellcheck source=dot-claude/hooks/guard-lib.sh
. "$(dirname -- "$0")/guard-lib.sh" 2> /dev/null || allow

# Tokenize each simple command to find a real `git checkout`/`git switch` and the
# branch it targets — a substring scan can't tell `echo git checkout main` or a
# commit message from the real thing. A leading `cd <path>` retargets the repo.
target=''
work_dir=''
segs=$(_split "$cmd")
while IFS= read -r seg; do
  [ -n "$seg" ] || continue
  set -f
  # shellcheck disable=SC2046 # intentional word-split: _norm emits space-separated tokens
  set -- $(_norm "$seg")
  set +f
  [ $# -gt 0 ] || continue
  # basename, so `/usr/bin/git` is git. _norm has already dropped `command`,
  # `env`, a leading `FOO=bar`, and shell-construct keywords.
  prog=${1##*/}
  if [ "$prog" = cd ] && [ -n "${2:-}" ]; then
    work_dir=$(_unquote "$2")
    case "$work_dir" in
      '~') work_dir=$HOME ;;
      '~'/*) work_dir=$HOME/${work_dir#'~'/} ;;
    esac
    continue
  fi
  [ "$prog" = git ] || continue
  shift
  set -f
  # shellcheck disable=SC2046 # intentional word-split: _skip_global emits space-separated tokens
  set -- $(_skip_global "$@")
  set +f
  [ "${1:-}" = checkout ] || [ "${1:-}" = switch ] || continue
  shift
  # Creating or detaching is never the reflex this guards, and never collides.
  cand=''
  pathmode=0
  positionals=0
  while [ $# -gt 0 ]; do
    case "$1" in
      -b | -B | -c | -C | --orphan) allow ;;
      --detach | -d) allow ;;
      --)
        pathmode=1
        break
        ;;
      # Redirections are not arguments. `git checkout feature-b 2>&1 | tail`
      # tokenizes a trailing `2>`, which would otherwise count as a second
      # positional and be misread as a path checkout. An operator that stands
      # alone (`>`, `2>`) also consumes the filename token after it.
      *'>'* | *'<'*)
        case "$1" in
          *'>' | *'<')
            shift
            [ $# -gt 0 ] && shift
            ;;
          *) shift ;;
        esac
        ;;
      -*) shift ;;
      *)
        positionals=$((positionals + 1))
        [ -z "$cand" ] && cand=$(_unquote "$1")
        shift
        ;;
    esac
  done
  # `git checkout <tree-ish> -- <path>` (and the `--`-less two-positional form)
  # RESTORES files from that ref. It does not check the branch out, it succeeds
  # against a branch held by another worktree (verified against real git), and it
  # is a working recovery move — denying it blocked real work.
  [ "$pathmode" = 1 ] && continue
  [ "$positionals" -gt 1 ] && continue
  if [ -n "$cand" ]; then
    target=$cand
    break
  fi
done << EOF
$segs
EOF
[ -n "$target" ] || allow

GIT() {
  if [ -n "$work_dir" ]; then
    git -C "$work_dir" "$@"
  else
    git "$@"
  fi
}

GIT rev-parse --is-inside-work-tree > /dev/null 2>&1 || allow

# Ask git the ACTUAL question instead of guessing from the branch name. The old
# check matched only the *default* branch inside a linked worktree, but git fails
# on a *condition* — any branch already checked out in another worktree. Measured
# over 43 real collisions: 9 were `main`, 34 were other branches, so the dominant
# population walked straight past. This is also strictly safer: it can only fire
# when the branch is genuinely held elsewhere, so it cannot false-positive, and it
# needs no regex escaping for branches like `release/1.0`.
GIT worktree list --porcelain 2> /dev/null | grep -qxF "branch refs/heads/${target}" || allow
[ "$(GIT symbolic-ref --quiet --short HEAD 2> /dev/null)" = "$target" ] && allow

holder=$(GIT worktree list --porcelain 2> /dev/null |
  awk -v b="branch refs/heads/${target}" '/^worktree /{w=substr($0,10)} $0==b{print w; exit}')
reason="\`${target}\` is already checked out in another worktree${holder:+ at ${holder}}, so \`git checkout ${target}\` / \`git switch ${target}\` fails with \"'${target}' is already used by worktree\". To inspect it read-only: git log ${target} / git diff ${target} (or git switch --detach ${target}). To do work, stay on your current branch."
jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0
