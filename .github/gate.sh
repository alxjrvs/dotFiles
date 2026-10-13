#!/bin/bash
# The repo settings that are not files, as one idempotent command run by the owner:
#   .github/gate.sh [owner/repo] [check]      (defaults: origin's repo, and `lint`)
# GitHub is the gate: the default branch takes pull requests only, squash-merged once GitHub
# Actions (app 15368) reports the one required check passing, with no bypass for anyone, the owner
# included; a status anyone else posts under that name blocks the merge. The branch need not be up
# to date, so parallel agent PRs never wait behind each other. The squash commit carries the PR's
# body, and a branch that fell behind can be updated from the PR. Actions tokens read by default,
# never approve a pull request, and run only SHA-pinned actions. Secret scanning and push
# protection stop a token before it lands, a reporter can file a vulnerability privately, and
# Dependabot's security updates skip its version cooldown. Rulesets on a private repo need a paid
# plan; everything here is free on a public one.
set -euo pipefail

settings='{
  "has_issues": true,
  "allow_auto_merge": true,
  "delete_branch_on_merge": true,
  "allow_squash_merge": true,
  "allow_merge_commit": false,
  "allow_rebase_merge": false,
  "allow_update_branch": true,
  "squash_merge_commit_title": "PR_TITLE",
  "squash_merge_commit_message": "PR_BODY"
}'
security='{"security_and_analysis": {
  "secret_scanning": { "status": "enabled" },
  "secret_scanning_push_protection": { "status": "enabled" }
}}'
actions='{ "enabled": true, "allowed_actions": "all", "sha_pinning_required": true }'
tokens='{ "default_workflow_permissions": "read", "can_approve_pull_request_reviews": false }'
ruleset() {
  cat << EOF
{
  "name": "default-branch-protection",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "required_status_checks", "parameters": {
        "strict_required_status_checks_policy": false,
        "do_not_enforce_on_create": false,
        "required_status_checks": [{ "context": "$1", "integration_id": 15368 }] } },
    { "type": "pull_request", "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false,
        "required_reviewers": [],
        "require_extra_approval_for_unattributed_changes": true,
        "allowed_merge_methods": ["squash"] } }
  ]
}
EOF
}

# A read gets one retry: a connection reset at wake is not drift. A 4xx is an answer, not retried.
api() {
  local out err try
  err=$(mktemp)
  for try in 1 2; do
    if out=$(gh api "$@" 2> "$err"); then
      rm -f "$err"
      [ -z "$out" ] || printf '%s\n' "$out"
      return 0
    fi
    grep -qE 'HTTP 4[0-9]{2}' "$err" && break
    [ "$try" = 2 ] || sleep 3
  done
  cat "$err" >&2
  rm -f "$err"
  return 1
}

# Every active ruleset that guards the default branch, whatever it is named: gate.sh keeps one. A
# disabled one guards nothing. Fails when a read fails.
guards() {
  local all
  all=$(api "repos/$1/rulesets" --jq '.[] | select(.target == "branch" and .enforcement == "active") | .id' 2>&1) || {
    # A private repo on a free plan has no rulesets to read: it was never gated.
    grep -qE 'HTTP 40[34]' <<< "$all" && return 0
    echo "$all" >&2 && return 1
  }
  for id in $all; do
    api "repos/$1/rulesets/$id" --jq \
      'select(.conditions.ref_name.include | any(. == "~DEFAULT_BRANCH" or . == "~ALL")) | .id' || return 1
  done
}

# How many `uses:` in the default branch's workflows name a tag or branch rather than a full SHA:
# requiring SHA pins turns each one red. Fails when a read fails; no workflows directory is zero.
unpinned() {
  local f files out n=0
  if ! files=$(api "repos/$1/contents/.github/workflows" --jq '.[] | select(.name | test("\\.ya?ml$")) | .path' 2>&1); then
    grep -q 'HTTP 404' <<< "$files" || return 1
    files=
  fi
  for f in $files; do
    out=$(api -H 'Accept: application/vnd.github.raw' "repos/$1/contents/$f") || return 1
    n=$((n + $(grep -E '^[^#]*uses:[[:space:]]*[^.[:space:]#][^@[:space:]]*@' <<< "$out" |
      grep -cvE '@[0-9a-f]{40}([^0-9a-f]|$)' || true)))
  done
  echo "$n"
}

# One write; a failure names itself.
write() { gh api "$@" > /dev/null || { echo "gate: $repo: gh api $* failed" >&2 && return 1; }; }

# The writes, for one repo and its required check. SHA pinning waits while a workflow still names a
# tag, so converging never turns that repo's CI red.
converge() {
  local repo=$1 name=$2 ids first n vis
  [[ $name != \<* ]] || { echo "gate: $name is a placeholder; name the repo's real check" >&2 && return 1; }
  write -X PATCH "repos/$repo" --input - <<< "$settings" || return 1
  vis=$(api "repos/$repo" --jq .visibility) || return 1
  # Free on a public repo only; a private one without Secret Protection answers 422.
  if [ "$vis" = public ]; then
    write -X PATCH "repos/$repo" --input - <<< "$security" || return 1
    write -X PUT "repos/$repo/private-vulnerability-reporting" || return 1
  fi
  write -X PUT "repos/$repo/vulnerability-alerts" || return 1
  write -X PUT "repos/$repo/automated-security-fixes" || return 1
  n=$(unpinned "$repo") || return 1
  if [ "$n" -eq 0 ]; then
    write -X PUT "repos/$repo/actions/permissions" --input - <<< "$actions" || return 1
  else
    echo "gate: $repo still names $n actions by tag; SHA pinning waits until a PR pins them"
  fi
  write -X PUT "repos/$repo/actions/permissions/workflow" --input - <<< "$tokens" || return 1

  ids=$(guards "$repo") || return 1
  first=${ids%%$'\n'*}
  if [ -n "$first" ]; then
    ruleset "$name" | write -X PUT "repos/$repo/rulesets/$first" --input - || return 1
  else
    ruleset "$name" | write -X POST "repos/$repo/rulesets" --input - || return 1
  fi
  # Rulesets aggregate, so another one guarding the branch keeps its rules; its owner decides.
  for id in $(tail -n +2 <<< "$ids"); do
    echo "gate: ruleset $id also guards $repo's default branch; review it in the repo's settings"
  done
  echo "gate: $repo converged"
}

repo=${1:-$(gh repo view "$(git remote get-url origin)" --json nameWithOwner --jq .nameWithOwner)}
converge "$repo" "${2:-lint}"
