#!/usr/bin/env bash
#
# covers: the sources below. `all.sh --changed <files>` reads these lines to
# decide whether this suite has anything to say about a change; with no
# argument every suite runs regardless. A suite that declares nothing always
# runs, so forgetting a line costs time, never coverage.
# covers: dot-claude/hooks/repo-scope-guard.sh
# Regression suite for repo-scope-guard.sh.
#
# Its own harness rather than a cases.tsv block: every verdict depends on which
# repo the working directory points at, so each case needs a real fixture with a
# real origin remote. No network — the guard resolves the owner from the local
# remote precisely so it never makes one. ~1s.
#
# READ THIS BEFORE TRUSTING A GREEN RUN. Most cases here assert the guard did
# NOT fire, and a hook that does nothing at all passes every one of them. Both
# negative controls were run, and these are their MEASURED results (2026-09-01,
# 30 cases) — the first draft of this block guessed 10 and 8, and both were
# wrong, which is the whole reason the convention is to run them rather than
# reason about them:
#
#   - stub hook (`exit 0` and nothing else): 16 failures, exactly the DENY cases.
#   - `_is_owned` forced to always return false (every owner foreign): 9
#     failures — the eight owned-org ALLOW cases plus `merge_plain`, which is
#     denied as a foreign write once no owner is owned. That control proves the
#     guard reads the owner rather than refusing every write, which would make
#     `gh` unusable.
#
# Re-run both if you change the guard. $1 overrides the hook path.
set -u

HERE=$(cd -- "$(dirname -- "$0")" && pwd)
HOOK=${1:-$(cd -- "$HERE/.." && pwd)/repo-scope-guard.sh}
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

mkrepo() { # $1 = dir name, $2 = origin url
  local d=$ROOT/$1
  mkdir -p "$d"
  gq "$d" init -q -b main
  gq "$d" config user.email t@example.com
  gq "$d" config user.name Test
  gq "$d" remote add origin "$2"
  printf '%s' "$d"
}

OWNED=$(mkrepo owned https://github.com/alxjrvs/dotFiles.git)
ORG=$(mkrepo org git@github.com:TheGnarCo/some-repo.git)
FOREIGN=$(mkrepo foreign https://github.com/someone-else/their-repo.git)
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
# --repo overrides the cwd, in both directions.
case_is explicit_foreign DENY "gh issue create --repo someone-else/thing --title x" "$OWNED"
case_is explicit_foreign_short DENY "gh issue create -R someone-else/thing --title x" "$OWNED"

# --- gh api: the path permissions.deny cannot cover --------------------------
case_is api_post_foreign DENY "gh api -X POST repos/someone-else/thing/issues -f title=x" "$OWNED"
case_is api_delete_foreign DENY "gh api -X DELETE repos/someone-else/thing/git/refs/heads/main" "$OWNED"
case_is api_field_foreign DENY "gh api repos/someone-else/thing/issues -f title=x" "$OWNED"

# REGRESSION: a full URL is the same endpoint with a host glued on, but no
# pattern matched a string starting with `https:`, so the guard fell back to the
# cwd's owner and ALLOWED the write.
case_is api_full_url_foreign DENY "gh api -X DELETE https://api.github.com/repos/someone-else/thing/issues/1" "$OWNED"
case_is api_full_url_post DENY "gh api -X POST https://api.github.com/repos/someone-else/thing/issues -f title=x" "$OWNED"
case_is api_full_url_owned ALLOW "gh api -X POST https://api.github.com/repos/alxjrvs/dotFiles/issues -f title=x" "$OWNED"

# REGRESSION: GraphQL names its target as a node ID inside the query body, so
# the owner is invisible by construction and the cwd fallback ALLOWED every
# mutation on GitHub. Refused rather than assumed safe.
case_is api_graphql_mutation DENY "gh api graphql -f query='mutation{addComment(input:{subjectId:\"XYZ\",body:\"hi\"}){clientMutationId}}'" "$OWNED"
case_is api_graphql_mutation_owned_cwd DENY "gh api graphql -f query='mutation { deleteRef(input:{refId:\"R\"}) { clientMutationId } }'" "$OWNED"
# A read-only GraphQL query is untouched — it is the mutation keyword that gates.
case_is api_graphql_query ALLOW "gh api graphql -f query='query{viewer{login}}'" "$OWNED"

# --- the same writes, inside the owned orgs, must pass -----------------------
case_is owned_issue ALLOW "gh issue create --title x --body y" "$OWNED"
case_is owned_pr ALLOW "gh pr create --fill" "$OWNED"
case_is org_issue ALLOW "gh issue create --title x" "$ORG"
case_is explicit_owned ALLOW "gh issue create --repo alxjrvs/boom --title x" "$FOREIGN"
case_is api_post_owned ALLOW "gh api -X POST repos/alxjrvs/dotFiles/issues -f title=x" "$OWNED"
# Case-insensitive: GitHub owners are.
case_is owner_case ALLOW "gh issue create --repo AlxJrvs/dotFiles --title x" "$FOREIGN"

# --- reads are never gated ---------------------------------------------------
case_is read_view ALLOW "gh pr view 1" "$FOREIGN"
case_is read_list ALLOW "gh issue list" "$FOREIGN"
case_is read_api ALLOW "gh api repos/someone-else/thing" "$FOREIGN"

# --- the branch-deleting merge, wherever it points ---------------------------
case_is merge_d DENY "gh pr merge 1 -d" "$OWNED"
case_is merge_delete_branch DENY "gh pr merge 1 --delete-branch" "$OWNED"
case_is merge_plain ALLOW "gh pr merge 1 --squash" "$OWNED"

# --- fail open ---------------------------------------------------------------
# No remote means no owner to judge; a guard that wedges the agent is worse than
# one that misses.
case_is no_remote ALLOW "gh issue create --title x" "$NOREMOTE"
# Prose naming the command is not the command.
case_is echo_prose ALLOW "echo gh issue create --repo someone-else/thing" "$OWNED"

if [ "$fail" -ne 0 ]; then
  echo "reposcope-tests: $pass passed, $fail FAILED$failures"
  exit 1
fi
echo "reposcope-tests: $pass passed"
