#!/usr/bin/env bash
# Claude Code PreToolUse guard — refuses a WRITE to a GitHub repo outside the
# owned orgs, and refuses the two `gh pr merge` flags that delete a branch.
#
# CLAUDE.md has carried both as prose. Neither was enforced, and one was worse
# than unenforced: `.claude/settings.local.json` pre-approved `Bash(gh api *)`,
# which is `-X POST` and `-X DELETE` against any repo on GitHub with no prompt,
# under `defaultMode: auto`. DECISIONS.md names `gh api` as the exact path a deny
# rule cannot cover, because deny matches a command SPELLING and the owner is an
# argument, not a spelling.
#
# WHY A GUARD AND NOT A DENY ENTRY. `permissions.deny` cannot express "this repo
# but not that one" (the owner is data), nor "this flag anywhere in argv"
# (`Bash(gh pr merge:*)` matches every spelling of it). Both need tokenizing,
# which is what guard-lib.sh is for.
#
# NO NETWORK. The owner is resolved from the local remote, never `gh repo view`:
# this runs on every Bash tool call, and a network round-trip there is a tax on
# every command to catch a rare one. A repo with no resolvable remote fails OPEN.
#
# FAILS OPEN on everything ambiguous — missing jq, non-repo cwd, an owner that
# cannot be resolved, an unrecognised subcommand. A guard that wedges the agent
# is worse than one that misses; the deny here is a floor under the common
# spellings, not a proof.
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

# shellcheck source=dot-claude/hooks/guard-lib.sh
. "$(dirname -- "$0")/guard-lib.sh" 2> /dev/null || allow

# `gh` subcommands that WRITE. Reads (`view`, `list`, `status`, `checks`, `diff`)
# are never gated: an agent must be able to look at anything, and the rule is
# about writing.
_is_write_verb() { # $1 = subcommand, $2 = verb
  case "$1 $2" in
    "issue create" | "issue edit" | "issue comment" | "issue close" | "issue reopen" | \
      "issue delete" | "issue transfer" | "issue pin" | "issue unpin" | "issue lock" | \
      "issue unlock") return 0 ;;
    "pr create" | "pr edit" | "pr comment" | "pr close" | "pr reopen" | "pr merge" | \
      "pr review" | "pr ready" | "pr lock" | "pr unlock") return 0 ;;
    "release create" | "release edit" | "release delete" | "release upload" | \
      "release delete-asset") return 0 ;;
    "repo create" | "repo edit" | "repo delete" | "repo rename" | "repo archive" | \
      "repo unarchive" | "repo fork" | "repo deploy-key") return 0 ;;
    "gist create" | "gist edit" | "gist delete") return 0 ;;
    "label create" | "label edit" | "label delete" | "label clone") return 0 ;;
    "secret set" | "secret delete" | "variable set" | "variable delete") return 0 ;;
    "workflow run" | "workflow enable" | "workflow disable") return 0 ;;
    "run cancel" | "run rerun" | "run delete") return 0 ;;
    "cache delete") return 0 ;;
    "ruleset "*) return 1 ;; # `gh ruleset` is read-only in gh
    *) return 1 ;;
  esac
}

# Owner of the repo this command targets: an explicit --repo wins, otherwise the
# origin remote of the working directory.
_owner_of() { # $1 = explicit repo arg (may be empty), $2 = work dir
  local r url
  r=$1
  if [ -n "$r" ]; then
    # OWNER/REPO, or a full URL.
    case $r in
      *github.com[:/]*) r=${r#*github.com} r=${r#:} r=${r#/} ;;
    esac
    printf '%s' "${r%%/*}"
    return 0
  fi
  url=$(git -C "$2" remote get-url origin 2> /dev/null) || return 1
  [ -n "$url" ] || return 1
  case $url in
    *github.com[:/]*) url=${url#*github.com} url=${url#:} url=${url#/} ;;
    *) return 1 ;;
  esac
  url=${url%.git}
  printf '%s' "${url%%/*}"
}

_is_owned() { # $1 = owner
  local o
  [ -n "$1" ] || return 1
  for o in $(_owned_orgs); do
    # Case-insensitive: GitHub owners are, and `Alxjrvs` must not read as foreign.
    [ "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$o" | tr '[:upper:]' '[:lower:]')" ] && return 0
  done
  return 1
}

DRAFT_IT="Draft it and show it first — CLAUDE.md requires express permission for a write outside the owned orgs. If this is intended, run it yourself, or say so and it can be added to _owned_orgs in guard-lib.sh."

segs=$(_split "$cmd")
segs=$(_expand_interpreters "$cmd" "$segs")

work_dir=$cwd
while IFS= read -r seg; do
  [ -n "$seg" ] || continue
  set -f
  # shellcheck disable=SC2046 # intentional word-split: _norm emits space-separated tokens
  set -- $(_norm "$seg")
  set +f
  [ $# -gt 0 ] || continue
  prog=${1##*/}

  # A leading `cd` retargets which repo the command acts on, exactly as in
  # rebase-guard.sh.
  if [ "$prog" = cd ] && [ -n "${2:-}" ]; then
    d=$(_unquote "$2")
    case $d in
      '~') d=$HOME ;;
      '~'/*) d=$HOME/${d#'~'/} ;;
    esac
    case $d in
      /*) work_dir=$d ;;
      *) work_dir=$work_dir/$d ;;
    esac
    continue
  fi

  [ "$prog" = gh ] || continue
  shift

  sub=${1:-}
  verb=${2:-}
  repo_arg=''
  merge_deletes=0

  # Sweep the whole argv for --repo/-R and, for `pr merge`, the delete flags.
  n=$#
  i=1
  while [ "$i" -le "$n" ]; do
    eval "a=\${$i}"
    a=$(_unquote "$a")
    case $a in
      --repo | -R)
        j=$((i + 1))
        if [ "$j" -le "$n" ]; then
          eval "repo_arg=\${$j}"
          repo_arg=$(_unquote "$repo_arg")
        fi
        ;;
      --repo=*) repo_arg=${a#--repo=} ;;
      -d | --delete-branch) merge_deletes=1 ;;
      --delete-branch=true) merge_deletes=1 ;;
    esac
    i=$((i + 1))
  done

  # --- the branch-deleting merge, wherever it points ------------------------
  if [ "$sub" = pr ] && [ "$verb" = merge ] && [ "$merge_deletes" = 1 ]; then
    deny "\`gh pr merge\` with a branch-deleting flag is refused: land work through GitHub's own gate and let \`delete_branch_on_merge\` handle the branch. A local flag deletes the branch before the stack above it has been retargeted, which is how a stacked PR loses its base. \`permissions.deny\` cannot express this — it matches a command spelling, and the flag is an argument."
  fi

  # --- writes outside the owned orgs ----------------------------------------
  gated=0
  if [ "$sub" = api ]; then
    # `gh api` is the path that walks past everything: the verb is a flag.
    i=1
    while [ "$i" -le "$n" ]; do
      eval "a=\${$i}"
      a=$(_unquote "$a")
      case $a in
        -X | --method)
          j=$((i + 1))
          if [ "$j" -le "$n" ]; then
            m=''
            # shellcheck disable=SC2154 # assigned by the eval on the next line
            eval "m=\${$j}"
            case $(_unquote "$m" | tr '[:lower:]' '[:upper:]') in
              POST | PATCH | PUT | DELETE) gated=1 ;;
            esac
          fi
          ;;
        -X*) case $(printf '%s' "${a#-X}" | tr '[:lower:]' '[:upper:]') in POST | PATCH | PUT | DELETE) gated=1 ;; esac ;;
        --method=*) case $(printf '%s' "${a#--method=}" | tr '[:lower:]' '[:upper:]') in POST | PATCH | PUT | DELETE) gated=1 ;; esac ;;
        -f | --field | --raw-field | --input)
          # gh sends POST implicitly when fields are supplied.
          gated=1
          ;;
      esac
      i=$((i + 1))
    done
    # The endpoint carries the owner: repos/OWNER/NAME/...
    if [ "$gated" = 1 ] && [ -z "$repo_arg" ]; then
      i=1
      while [ "$i" -le "$n" ]; do
        eval "a=\${$i}"
        a=$(_unquote "$a")
        case $a in
          repos/*/*) repo_arg=${a#repos/} ;;
          /repos/*/*) repo_arg=${a#/repos/} ;;
        esac
        i=$((i + 1))
      done
    fi
  elif _is_write_verb "$sub" "$verb"; then
    gated=1
  fi

  [ "$gated" = 1 ] || continue

  owner=$(_owner_of "$repo_arg" "$work_dir") || continue
  [ -n "$owner" ] || continue
  _is_owned "$owner" && continue

  deny "\`gh $sub $verb\` writes to \`$owner\`, which is outside the owned orgs ($(_owned_orgs | tr '\n' ' ')). $DRAFT_IT"
done << EOF
$segs
EOF

allow
