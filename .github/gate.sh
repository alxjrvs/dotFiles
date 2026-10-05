#!/bin/bash
# The repo settings that are not files, as one idempotent command run by the owner:
#   .github/gate.sh [owner/repo] [check]      (defaults: origin's repo, and `lint`)
#   .github/gate.sh --check <owner/repo | owner>...   read-only; exits 1 on drift, naming the fix
#   .github/gate.sh --apply <owner/repo | owner>...   converges every drifted repo it safely can
# GitHub is the gate: the default branch takes pull requests only, squash-merged once GitHub
# Actions (app 15368) reports the one required check passing, with no bypass for anyone, the owner
# included; a status anyone else posts under that name blocks the merge. The branch need not be up
# to date: parallel agent PRs would otherwise wait behind each other, and main-green.sh holds the
# nightly converge until main itself has passed. The squash commit carries the PR's body, a branch that fell behind can be updated from
# the PR, and Issues stay on for upkeep's failure reports. Actions tokens read by default, never
# approve a pull request, and run only SHA-pinned actions. Secret scanning and push protection stop
# a token before it lands, a reporter can file a vulnerability privately, and Dependabot's security
# updates skip its version cooldown. Rulesets on a private repo need a paid plan; everything here is
# free on a public one.
set -euo pipefail

# Named from the clone's root: fix lines reach upkeep's public issue, and an absolute path would
# name the Mac's account.
self=.github/gate.sh
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

# Whether $1 holds $2: the live state, projected onto the keys $2 declares, equals $2. A key GitHub
# adds on its own (a ruleset's newer pull_request parameters) is not drift; an array keeps its
# exact length, so an extra rule, required check, merge method or bypass actor is.
holds() {
  jq -e --argjson want "$2" '
    def norm: if type == "object" and has("rules") then .rules |= sort_by(.type) else . end;
    def proj($w):
      if ($w | type) == "object" and type == "object" then
        . as $h | reduce ($w | keys[]) as $k ({}; .[$k] = ($h[$k] | proj($w[$k])))
      elif ($w | type) == "array" and type == "array" and length == ($w | length) then
        . as $h | [range(length) as $i | $h[$i] | proj($w[$i])]
      else . end;
    ($want | norm) as $w | (norm | proj($w)) == $w
  ' <<< "$1" > /dev/null
}

# One line for a repo that does not hold: its drift and fix, an active public repo with no ruleset,
# or a read that failed. A private repo's line is tagged, so upkeep's public issue leaves it out.
# Sets `state` (ok, drift, unreadable) and `name` (the required check, when one is known).
check() {
  local repo=$1 ids id live meta tag=gate perms va n drift=()
  local unreadable="gate (unreadable): $repo; run $self --check $repo again"
  state=unreadable name=
  if ! meta=$(api "repos/$repo") || ! ids=$(guards "$repo"); then
    echo "$unreadable"
    return 1
  fi
  [ "$(jq -r .visibility <<< "$meta")" = public ] || tag="gate (private)"
  if [ -z "$ids" ]; then
    state=ok
    # Rulesets are free on a public repo: one pushed to this half-year with none takes direct pushes.
    [ "$tag" = gate ] && jq -e '(.pushed_at // "1970-01-01T00:00:00Z" | fromdateiso8601) > (now - 180 * 86400)' <<< "$meta" > /dev/null || return 0
    state=drift
    echo "gate: $repo has no ruleset; pick its aggregate check, then run $self $repo <check>"
    return 1
  fi
  [ "$(wc -l <<< "$ids")" -eq 1 ] || drift+=("$(wc -l <<< "$ids" | tr -d ' ') rulesets guard the default branch")
  # The ruleset that requires a check names it; with none, the owner picks the aggregate job.
  for id in $ids; do
    live=$(api "repos/$repo/rulesets/$id") || {
      echo "$unreadable"
      return 1
    }
    name=$(jq -r '[.rules[] | select(.type == "required_status_checks")
      | .parameters.required_status_checks[0].context][0] // empty' <<< "$live")
    [ -z "$name" ] || break
  done
  holds "$live" "$(ruleset "$name")" || drift+=("ruleset")
  holds "$meta" "$settings" || drift+=("merge settings")
  if [ "$tag" = gate ]; then
    holds "$meta" "$security" || drift+=("push protection")
    live=$(api "repos/$repo/private-vulnerability-reporting") || {
      echo "$unreadable"
      return 1
    }
    holds "$live" '{"enabled": true}' || drift+=("private reporting")
  fi
  perms=$(api "repos/$repo/actions/permissions") || {
    echo "$unreadable"
    return 1
  }
  if ! holds "$perms" "$actions"; then
    n=$(unpinned "$repo")
    if [ "$n" -gt 0 ]; then drift+=("action pinning: pin $n uses: to SHAs first"); else drift+=("action pinning"); fi
  fi
  live=$(api "repos/$repo/actions/permissions/workflow") || {
    echo "$unreadable"
    return 1
  }
  holds "$live" "$tokens" || drift+=("token permissions")
  # 204 when on, 404 when off; anything else is a failed read.
  if ! va=$(api --silent "repos/$repo/vulnerability-alerts" 2>&1); then
    grep -q 'HTTP 404' <<< "$va" || {
      echo "$unreadable"
      return 1
    }
    drift+=("Dependabot alerts")
  fi
  live=$(api "repos/$repo/automated-security-fixes") || {
    echo "$unreadable"
    return 1
  }
  holds "$live" '{"enabled": true, "paused": false}' || drift+=("security updates")
  state=ok
  [ ${#drift[@]} -eq 0 ] && return 0
  state=drift
  local IFS=,
  if [ -n "$name" ]; then
    echo "$tag: $repo drifted (${drift[*]}); fix: ! $self $repo \"$name\""
  else
    echo "$tag: $repo drifted (${drift[*]}); pick its aggregate check, then run $self $repo <check>"
  fi
  return 1
}

repos() {
  if [[ $1 == */* ]]; then
    echo "$1"
  else
    gh repo list "$1" --no-archived --source --limit 500 --json nameWithOwner --jq '.[].nameWithOwner'
  fi
}

# One write; a failure names itself and fails the repo. converge runs where errexit is off (after
# `&&`), so each write is checked here.
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

case ${1:-} in
  --check | --apply)
    mode=$1
    shift
    failed=0
    for target in "$@"; do
      # A listing that fails is not an owner with nothing to check.
      if ! list=$(repos "$target"); then
        echo "gate (unreadable): $target"
        failed=1
        continue
      fi
      for repo in $list; do
        check "$repo" && continue
        if [ "$mode" = --apply ] && [ "$state" = drift ] && [ -n "$name" ]; then
          converge "$repo" "$name" && continue
        fi
        failed=1
      done
    done
    exit "$failed"
    ;;
esac

repo=${1:-$(gh repo view "$(git remote get-url origin)" --json nameWithOwner --jq .nameWithOwner)}
converge "$repo" "${2:-lint}"
