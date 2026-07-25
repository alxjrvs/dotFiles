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

# Tokenize each simple command to find a real `git checkout`/`git switch` and the
# branch it targets — a substring scan can't tell `echo git checkout main` or a
# commit message from the real thing. A leading `cd <path>` retargets the repo.
target=''
work_dir=''
segs=$(printf '%s' "$cmd" | sed -E 's/(\|\||&&|[;&|])/\n/g')
while IFS= read -r seg; do
  seg="${seg#"${seg%%[![:space:]]*}"}"
  [ -n "$seg" ] || continue
  set -f
  # shellcheck disable=SC2086 # intentional word-split of one shell segment
  set -- $seg
  set +f
  prog=${1:-}
  if [ "$prog" = cd ] && [ -n "${2:-}" ]; then
    work_dir=$2
    work_dir=${work_dir%\"}
    work_dir=${work_dir#\"}
    case "$work_dir" in
      '~') work_dir=$HOME ;;
      '~'/*) work_dir=$HOME/${work_dir#'~'/} ;;
    esac
    continue
  fi
  [ "$prog" = git ] || continue
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      -C | -c | --git-dir | --work-tree | --namespace | --exec-path)
        shift
        [ $# -gt 0 ] && shift
        ;;
      -*) shift ;;
      *) break ;;
    esac
  done
  [ "${1:-}" = checkout ] || [ "${1:-}" = switch ] || continue
  shift
  # Creating or detaching is never the reflex this guards, and never collides.
  while [ $# -gt 0 ]; do
    case "$1" in
      -b | -B | -c | -C | --orphan) allow ;;
      --detach | -d) allow ;;
      --) break ;;
      -*) shift ;;
      *)
        target=$1
        break
        ;;
    esac
  done
  [ -n "$target" ] && break
done << EOF
$segs
EOF
[ -n "$target" ] || allow
# Strip quotes so `git checkout "main"` — an accepted false negative before — is
# now caught like any other spelling.
target=${target%\"}
target=${target#\"}
target=${target%\'}
target=${target#\'}

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
