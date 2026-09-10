#!/usr/bin/env bash
# Regression suite for repo-scope-guard.sh. Every verdict depends on which repo the working
# directory points at, so each case has a real fixture with a real remote. No network. ~1s.
#
# Most cases assert the guard did NOT fire, and a hook that does nothing passes every one of
# them. Before trusting a green run after a change, run the two negative controls: a stub hook
# (`exit 0` only) must fail exactly the DENY cases, and `_is_owned` forced false must fail the
# owned-org ALLOW cases. $1 overrides the hook path.
set -u

HERE=$(cd -- "$(dirname -- "$0")" && pwd)
HOOK=${1:-$(cd -- "$HERE/.." && pwd)/executable_repo-scope-guard.sh}
[ -x "$HOOK" ] || {
  echo "reposcope-tests: no executable hook at $HOOK" >&2
  exit 2
}

for v in $(env | sed -n 's/^\(GIT_[A-Za-z0-9_]*\)=.*/\1/p'); do
  unset "$v" 2> /dev/null || true
done
unset CDPATH
export GIT_CONFIG_NOSYSTEM=1
export HOME=${TMPDIR:-/tmp}/reposcope-tests-home.$$
mkdir -p "$HOME"

command -v jq > /dev/null 2>&1 || {
  echo "reposcope-tests: jq is required" >&2
  exit 2
}

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/reposcope-tests.XXXXXX") || exit 2
cleanup() { rm -rf "$ROOT" "$HOME"; }
trap cleanup EXIT INT TERM

gq() { git -C "$1" "${@:2}" > /dev/null 2>&1; }

pass=0
fail=0
failures=''
note() {
  fail=$((fail + 1))
  failures="${failures}
  [$1] $2"
}
ok() { pass=$((pass + 1)); }

mkrepo() { # $1 = dir name, $2 = origin url, $3 = upstream url (optional)
  local d=$ROOT/$1
  mkdir -p "$d"
  gq "$d" init -q -b main
  gq "$d" config user.email t@example.com
  gq "$d" config user.name Test
  gq "$d" remote add origin "$2"
  [ -n "${3:-}" ] && gq "$d" remote add upstream "$3"
  printf '%s' "$d"
}

OWNED=$(mkrepo owned https://github.com/alxjrvs/dotFiles.git)
ORG=$(mkrepo org git@github.com:TheGnarCo/some-repo.git)
FOREIGN=$(mkrepo foreign https://github.com/someone-else/their-repo.git)
FORK=$(mkrepo fork https://github.com/alxjrvs/theirlib.git https://github.com/someone-else/theirlib.git)
NOREMOTE=$ROOT/noremote
mkdir -p "$NOREMOTE"
gq "$NOREMOTE" init -q -b main

verdict() { # $1 = command, $2 = cwd
  local out
  out=$(jq -cn --arg c "$1" --arg d "$2" \
    '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:$d,tool_input:{command:$c}}' |
    "$HOOK" 2> /dev/null)
  if [ -n "$out" ]; then printf 'DENY'; else printf 'ALLOW'; fi
}

case_is() { # $1 = name, $2 = expected, $3 = command, $4 = cwd
  local got
  got=$(verdict "$3" "$4")
  if [ "$got" = "$2" ]; then ok; else note "$1" "expected $2, got $got: $3"; fi
}

# --- writes to a foreign repo ------------------------------------------------
case_is foreign_issue DENY "gh issue create --title x --body y" "$FOREIGN"
case_is foreign_pr DENY "gh pr create --fill" "$FOREIGN"
case_is foreign_comment DENY "gh pr comment 1 --body hi" "$FOREIGN"
case_is foreign_review DENY "gh pr review 1 --approve" "$FOREIGN"
case_is foreign_release DENY "gh release create v1" "$FOREIGN"
case_is explicit_foreign DENY "gh issue create --repo someone-else/thing --title x" "$OWNED"
case_is explicit_foreign_short DENY "gh issue create -R someone-else/thing --title x" "$OWNED"
# `GH_REPO=` retargets gh exactly like --repo.
case_is env_repo_foreign DENY "GH_REPO=someone-else/thing gh issue create --title x" "$OWNED"
# A fork's PR and comments go to upstream, so upstream decides.
case_is fork_pr_upstream DENY "gh pr create --fill" "$FORK"
case_is fork_comment_upstream DENY "gh pr comment 1 --body hi" "$FORK"
# The wrapper spellings a bare comparison misses.
case_is foreign_env_wrapper DENY "env gh issue create --title x" "$FOREIGN"
case_is foreign_abs_path DENY "/opt/homebrew/bin/gh issue create --title x" "$FOREIGN"
case_is foreign_after_and DENY "git push && gh pr create --fill" "$FOREIGN"
# `op run -- CMD` runs CMD: the program to judge is gh, not op.
case_is op_run_wrapper DENY "op run --env-file=.env -- gh issue create --title x" "$FOREIGN"
case_is op_run_wrapper_owned ALLOW "op run --env-file=.env -- gh issue create --title x" "$OWNED"

# --- gh api: the path permissions.deny cannot cover --------------------------
case_is api_post_foreign DENY "gh api -X POST repos/someone-else/thing/issues -f title=x" "$OWNED"
case_is api_delete_foreign DENY "gh api -X DELETE repos/someone-else/thing/git/refs/heads/main" "$OWNED"
case_is api_field_foreign DENY "gh api repos/someone-else/thing/issues -f title=x" "$OWNED"
case_is api_full_url_foreign DENY "gh api -X DELETE https://api.github.com/repos/someone-else/thing/issues/1" "$OWNED"
case_is api_full_url_owned ALLOW "gh api -X POST https://api.github.com/repos/alxjrvs/dotFiles/issues -f title=x" "$OWNED"
case_is api_graphql_mutation DENY "gh api graphql -f query='mutation{addComment(input:{subjectId:\"XYZ\",body:\"hi\"}){clientMutationId}}'" "$OWNED"
case_is api_graphql_query ALLOW "gh api graphql -f query='query{viewer{login}}'" "$OWNED"
# gh's own placeholders mean the current repo: owned cwd allows, foreign cwd denies.
case_is api_placeholder_owned ALLOW "gh api repos/{owner}/{repo}/issues -f title=x" "$OWNED"
case_is api_placeholder_foreign DENY "gh api repos/{owner}/{repo}/issues -f title=x" "$FOREIGN"

# --- the same writes, inside the owned orgs, must pass -----------------------
case_is owned_issue ALLOW "gh issue create --title x --body y" "$OWNED"
case_is owned_pr ALLOW "gh pr create --fill" "$OWNED"
case_is org_issue ALLOW "gh issue create --title x" "$ORG"
case_is explicit_owned ALLOW "gh issue create --repo alxjrvs/oberon --title x" "$FOREIGN"
case_is env_repo_owned ALLOW "GH_REPO=alxjrvs/oberon gh issue create --title x" "$FOREIGN"
case_is api_post_owned ALLOW "gh api -X POST repos/alxjrvs/dotFiles/issues -f title=x" "$OWNED"
case_is owner_case ALLOW "gh issue create --repo AlxJrvs/dotFiles --title x" "$FOREIGN"
case_is merge_plain ALLOW "gh pr merge 1 --squash" "$OWNED"

# --- reads are never gated ---------------------------------------------------
case_is read_view ALLOW "gh pr view 1" "$FOREIGN"
case_is read_list ALLOW "gh issue list" "$FOREIGN"
case_is read_api ALLOW "gh api repos/someone-else/thing" "$FOREIGN"

# --- fail open ---------------------------------------------------------------
case_is no_remote ALLOW "gh issue create --title x" "$NOREMOTE"
case_is echo_prose ALLOW "echo gh issue create --repo someone-else/thing" "$OWNED"
case_is commit_prose ALLOW "git commit -m 'gh pr create && gh issue create'" "$FOREIGN"
case_is word_light ALLOW "echo light right digit" "$FOREIGN"

if [ "$fail" -ne 0 ]; then
  echo "reposcope-tests: $pass passed, $fail FAILED$failures"
  exit 1
fi
echo "reposcope-tests: $pass passed"
