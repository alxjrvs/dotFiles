#!/usr/bin/env bash
# Claude Code PreToolUse guard — refuses to destroy a worktree whose lock names a
# LIVE process. That is another session's in-flight work, and unlike every other
# irreversible action this repo guards, there is no PR and no reflog to recover
# from: the commits may exist nowhere else, and the working tree certainly does
# not.
#
# SCOPE. Plain `git worktree remove` already refuses a locked worktree — git does
# that itself, and Claude Code locks every agent worktree while its session runs.
# So this guard exists for the two spellings that walk past that refusal:
#
#   git worktree remove --force <path>     git's own check, explicitly overridden
#   rm -rf <path>                          git never consulted at all
#
# `git worktree prune --expire=now` is included because it removes the ADMIN dir
# for a worktree whose directory is momentarily unreachable, which unregisters a
# live session's worktree without touching its files — the same loss, quieter.
#
# FAILS OPEN, like every guard here: a missing jq, a non-repo cwd, an
# unresolvable path, a worktree with no lock file, or a lock naming a dead pid
# all pass through. "No lock file" is the normal state of a worktree nobody is
# working in.
set -u

allow() { exit 0; }

deny() {
  jq -cn --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2> /dev/null) || allow
[ -n "$cmd" ] || allow

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2> /dev/null) || allow
[ -n "$cwd" ] || cwd=$PWD
cd "$cwd" 2> /dev/null || allow

# shellcheck source=dot-claude/hooks/guard-lib.sh
. "$(dirname -- "$0")/guard-lib.sh" 2> /dev/null || allow

# The admin directory lives beside the PRIMARY checkout, not in the linked
# worktree's own .git file — `--git-common-dir` is what resolves that from either.
common=$(git rev-parse --git-common-dir 2> /dev/null) || allow
[ -n "$common" ] || allow
case $common in
  /*) ;;
  *) common=$(cd "$common" 2> /dev/null && pwd -P) || allow ;;
esac

# Is the worktree named by $1 locked by a process that is still running?
# Prints the lock text when it is; silent otherwise.
live_lock() { # $1 = candidate worktree path
  local p name lock pid
  p=${1%/}
  [ -n "$p" ] || return 1
  name=${p##*/}
  [ -n "$name" ] || return 1
  lock=$common/worktrees/$name/locked
  [ -f "$lock" ] || return 1
  # Claude Code writes: `claude session <name> (pid 63291 start <date>)`.
  # Any other lock text is still a lock, but without a pid there is nothing to
  # test, so it is left alone rather than guessed at.
  pid=$(sed -n 's/.*[( ]pid \([0-9][0-9]*\).*/\1/p' "$lock" 2> /dev/null)
  [ -n "$pid" ] || return 1
  kill -0 "$pid" 2> /dev/null || return 1
  printf '%s' "$(cat "$lock" 2> /dev/null)"
}

segs=$(_split "$cmd")
segs=$(_expand_interpreters "$cmd" "$segs")

while IFS= read -r seg; do
  [ -n "$seg" ] || continue
  set -f
  # shellcheck disable=SC2046 # intentional word-split: _norm emits space-separated tokens
  set -- $(_norm "$seg")
  set +f
  [ $# -gt 0 ] || continue
  prog=${1##*/}

  case $prog in
    git)
      shift
      # shellcheck disable=SC2046 # intentional word-split
      set -- $(_skip_global "$@")
      [ "${1:-}" = worktree ] || continue
      shift
      sub=${1:-}
      shift 2> /dev/null || true

      if [ "$sub" = prune ]; then
        for a in "$@"; do
          case $(_unquote "$a") in
            --expire=now | --expire=all)
              deny "\`git worktree prune --expire=now\` unregisters worktrees whose directory is momentarily unreachable, including ones a live session is using. The session keeps working against an admin dir that no longer exists. Prune with the default expiry, or remove a specific worktree by name."
              ;;
          esac
        done
        continue
      fi

      [ "$sub" = remove ] || continue
      forced=0
      for a in "$@"; do
        case $(_unquote "$a") in
          -f | --force) forced=1 ;;
        esac
      done
      for a in "$@"; do
        t=$(_unquote "$a")
        case $t in
          -*) continue ;;
        esac
        held=$(live_lock "$t") || continue
        [ -n "$held" ] || continue
        if [ "$forced" = 1 ]; then
          deny "\`git worktree remove --force\` targets a worktree held by a LIVE process — $held. git refuses this without --force for exactly this reason; the flag overrides the check, not the risk. Its commits may exist nowhere else and its working tree exists nowhere else. Wait for that session to finish, or close it first."
        fi
      done
      ;;
    rm)
      # `rm -rf <worktree>` never consults git at all, so git's own refusal
      # cannot help. Only recursive+force removals are considered: a plain `rm`
      # cannot delete a directory, and this guard has no business inspecting
      # ordinary file deletion.
      recursive=0
      for a in "$@"; do
        case $(_unquote "$a") in
          -rf | -fr | -Rf | -fR) recursive=1 ;;
          -r | -R | --recursive) recursive=1 ;;
        esac
      done
      [ "$recursive" = 1 ] || continue
      for a in "$@"; do
        t=$(_unquote "$a")
        case $t in
          -*) continue ;;
        esac
        held=$(live_lock "$t") || continue
        [ -n "$held" ] || continue
        deny "\`rm -rf\` targets a worktree held by a LIVE process — $held. This bypasses git entirely, so nothing else will stop it: the working tree is gone, and any commit not pushed is gone with it. Wait for that session to finish, or close it first."
      done
      ;;
  esac
done << EOF
$segs
EOF

allow
