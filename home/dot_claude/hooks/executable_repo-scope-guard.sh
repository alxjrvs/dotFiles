#!/usr/bin/env bash
# Claude Code PreToolUse guard: refuses a `gh` WRITE to a GitHub repo outside the owned orgs.
#
# WHY A GUARD AND NOT A DENY ENTRY. In an agent session `gh` runs with the human's token, which
# reaches every repo on GitHub, and `permissions.deny` cannot express "this owner but not that
# one": the owner is data (an argument, a remote, an endpoint path), so it has to be read.
# `gh api` is the sharpest case: `-X POST` / `-X DELETE` against any repo, owner in the path.
#
# NO NETWORK. The owner comes from the working directory's remotes (`upstream` first, then
# `origin`, because a fork's writes target upstream), an explicit `--repo`/`-R`, a `GH_REPO=`
# prefix, or a `repos/OWNER/NAME` endpoint. Never `gh repo view`: this runs on every `gh`
# command.
#
# FAILS OPEN on everything ambiguous: missing jq, a cwd outside a repo, an owner that cannot be
# resolved, an unrecognised subcommand, a command hidden inside an interpreter. A guard that
# wedges the agent is worse than one that misses; this is a floor under the common spellings.
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

# Cheap bail-out before any tokenizing: no `gh` as a word, no opinion. The handler's `if` rule
# is a substring match, so "light" and "right" arrive here too.
printf '%s' "$cmd" | grep -qE '(^|[^A-Za-z0-9_.-])gh([^A-Za-z0-9_.-]|$)' || allow

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2> /dev/null) || allow
[ -n "$cwd" ] || cwd=$PWD

# shellcheck source=home/dot_claude/hooks/guard-lib.sh
. "$(dirname -- "$0")/guard-lib.sh" 2> /dev/null || allow

# `gh` subcommands that WRITE. Reads are never gated: an agent must be able to look at anything.
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
      "repo unarchive" | "repo deploy-key") return 0 ;;
    "gist create" | "gist edit" | "gist delete") return 0 ;;
    "label create" | "label edit" | "label delete" | "label clone") return 0 ;;
    "secret set" | "secret delete" | "variable set" | "variable delete") return 0 ;;
    "workflow run" | "workflow enable" | "workflow disable") return 0 ;;
    "run cancel" | "run rerun" | "run delete") return 0 ;;
    "cache delete") return 0 ;;
    *) return 1 ;;
  esac
}

_owner_from_url() { # $1 = OWNER/REPO or a GitHub URL -> owner
  local r=$1
  case $r in
    *github.com[:/]*) r=${r#*github.com} r=${r#:} r=${r#/} ;;
  esac
  printf '%s' "${r%%/*}"
}

# Owner of the repo this command targets: an explicit repo wins; otherwise the work dir's
# `upstream` remote, then `origin`. Empty when nothing resolves (the caller fails open).
_owner_of() { # $1 = explicit repo (may be empty), $2 = work dir
  local url
  if [ -n "$1" ]; then
    _owner_from_url "$1"
    return 0
  fi
  url=$(git -C "$2" remote get-url upstream 2> /dev/null) ||
    url=$(git -C "$2" remote get-url origin 2> /dev/null) || return 1
  case $url in
    *github.com[:/]*) _owner_from_url "${url%.git}" ;;
    *) return 1 ;;
  esac
}

_is_owned() { # $1 = owner
  local o
  [ -n "$1" ] || return 1
  for o in $(_owned_orgs); do
    # Case-insensitive: GitHub owners are.
    [ "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$o" | tr '[:upper:]' '[:lower:]')" ] && return 0
  done
  return 1
}

DRAFT_IT="Draft it and show it first: a write outside the owned orgs needs express permission. If this is intended, run it yourself, or say so and it can be added to _owned_orgs in guard-lib.sh."

work_dir=$cwd
while IFS= read -r seg; do
  [ -n "$seg" ] || continue
  # A `GH_REPO=` prefix retargets gh like `--repo` does; _norm drops assignments, so read it first.
  env_repo=$(printf '%s' "$seg" | sed -n 's/.*[[:space:]]GH_REPO=\([^[:space:]]*\).*/\1/p; s/^GH_REPO=\([^[:space:]]*\).*/\1/p' | head -1)
  set -f
  # shellcheck disable=SC2046 # intentional word-split: _norm emits space-separated tokens
  set -- $(_norm "$seg")
  set +f
  [ $# -gt 0 ] || continue
  prog=${1##*/}

  # A leading `cd` retargets which repo the command acts on.
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
  repo_arg=$(_unquote "$env_repo")

  # Sweep argv for --repo/-R.
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
    esac
    i=$((i + 1))
  done
  # gh's own `{owner}/{repo}` placeholders mean "the current repo": resolve from the work dir.
  case $repo_arg in *'{owner}'*) repo_arg='' ;; esac

  gated=0
  if [ "$sub" = api ]; then
    # The verb is a flag, and gh POSTs implicitly when fields are supplied.
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
        -f | --field | --raw-field | --input | -F) gated=1 ;;
      esac
      i=$((i + 1))
    done
    # The endpoint carries the owner: repos/OWNER/NAME/..., with or without a host.
    if [ "$gated" = 1 ] && [ -z "$repo_arg" ]; then
      i=1
      while [ "$i" -le "$n" ]; do
        eval "a=\${$i}"
        a=$(_unquote "$a")
        case $a in
          https://api.github.com/*) a=${a#https://api.github.com/} ;;
          http://api.github.com/*) a=${a#http://api.github.com/} ;;
        esac
        case $a in
          repos/'{owner}'/*) ;;
          repos/*/*) repo_arg=${a#repos/} ;;
          /repos/*/*) repo_arg=${a#/repos/} ;;
        esac
        i=$((i + 1))
      done
    fi
    # GraphQL names its target as a node ID inside the query, so no path-based guard can scope a
    # mutation; refused rather than assumed safe. A read-only query is untouched.
    if [ "$gated" = 1 ] && [ -z "$repo_arg" ]; then
      case " $* " in
        *' graphql '*)
          if printf '%s' "$*" | grep -qE 'mutation[[:space:]{(]'; then
            deny "\`gh api graphql\` is carrying a mutation, and a GraphQL mutation names its target as a node ID inside the query, so no guard can tell which repo it writes to. Use the REST endpoint (\`gh api repos/OWNER/NAME/...\`), which carries the owner in the path. $DRAFT_IT"
          fi
          ;;
      esac
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
$(_split "$cmd")
EOF

allow
