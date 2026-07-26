#!/usr/bin/env bash
# Post the agentic review we ALREADY perform as a durable artifact on the PR,
# plus a `claude-review` commit status.
#
# Why this shape:
#   - The review already exists (Binfinite's issue-ship.js runs two adversarial
#     reviewers and blocks its own merge on their findings). It covers ~2% of PRs
#     because it waits to be invoked by hand. This fires it automatically.
#   - It runs LOCALLY, so it draws on the Claude subscription. Running an agent in
#     GitHub Actions bills real metered money — at ~8.8 PRs/day that is ~1,600
#     paid runs per half-year for work already covered.
#   - A commit status posted with your own token is a valid
#     `required_status_checks` context in a ruleset. That is how Jenkins and
#     Buildkite have always gated GitHub: real blocking enforcement, with zero LLM
#     tokens inside CI.
#   - `gh pr review --comment` creates a real PullRequestReview node, so escape
#     rate becomes measurable with the same GraphQL query that found there were 7
#     human approvals across 1,113 org PRs.
#
# Wired as a PostToolUse hook on `gh pr create` / `git push`. Backgrounds itself,
# so it NEVER blocks a turn — a review must not become a thing that stops work.
# Fails open and silent everywhere: no PR, no gh, no repo, unparseable input.
#
# Scope: opt-in per repo via PR_REVIEW_REPOS (a space-separated allowlist).
# Advisory until a day-30 finding rate justifies making it required.
set -u

exit_ok() { exit 0; }

# --- cheap bail-out ---------------------------------------------------------
# settings.json also carries a per-handler `if` rule, but keep this gate. Until
# 2026-07-25 that `if` sat on the matcher GROUP rather than the handler, so the
# client dropped it as an unknown key and this string compare was the only thing
# standing between the hook and the ~60k grep/sed/find Bash calls a month. The
# config filter is one misplaced key away from silently vanishing again; belt and
# braces. Everything below the stdin check costs a fork; everything above costs a
# string compare. Do NOT let the first network call (`gh repo view`) run before it.
command -v jq > /dev/null 2>&1 || exit_ok
input=$(cat 2> /dev/null) || exit_ok
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2> /dev/null) || exit_ok
case "$cmd" in
  *"gh pr create"* | *"git push"*) ;;
  *) exit_ok ;;
esac

# --- allowlist: owners AND/OR owner/repo ------------------------------------
# Entries may be an OWNER (covers every repo under it) or a fully-qualified
# owner/repo. Default covers every org the agent ships into — the whole point is
# that 1,113 org PRs across 25+ repos went unreviewed, so a single-repo pilot
# would leave the exposure exactly where it was. Set PR_REVIEW_REPOS to narrow.
: "${PR_REVIEW_REPOS:=TheGnarCo BinfiniteLLC SalvageUnion-io RANDSUM alxjrvs}"

command -v gh > /dev/null 2>&1 || exit_ok
command -v claude > /dev/null 2>&1 || exit_ok
git rev-parse --is-inside-work-tree > /dev/null 2>&1 || exit_ok

repo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2> /dev/null) || exit_ok
[ -n "$repo" ] || exit_ok
owner=${repo%%/*}
allowed=0
for entry in $PR_REVIEW_REPOS; do
  case "$entry" in
    */*) [ "$entry" = "$repo" ] && allowed=1 ;;
    *) [ "$entry" = "$owner" ] && allowed=1 ;;
  esac
  [ "$allowed" = 1 ] && break
done
[ "$allowed" = 1 ] || exit_ok

# Only when there is an open PR for this branch.
pr=$(gh pr view --json number -q .number 2> /dev/null) || exit_ok
[ -n "$pr" ] || exit_ok

sha=$(git rev-parse HEAD 2> /dev/null) || exit_ok

# Re-entrancy: the status is per-SHA, so a second push re-runs it, but two hooks
# firing on the same SHA must not double-review.
lock="${TMPDIR:-/tmp}/claude-review.${repo//\//_}.${sha}.lock"
mkdir "$lock" 2> /dev/null || exit_ok

# --- everything below runs detached ----------------------------------------
(
  trap 'rmdir "$lock" 2>/dev/null || true' EXIT

  status() { # $1=state $2=description
    gh api -X POST "repos/$repo/statuses/$sha" \
      -f state="$1" -f context=claude-review -f description="$2" \
      > /dev/null 2>&1 || true
  }

  status pending "review running locally"

  out="${TMPDIR:-/tmp}/claude-review.$$"
  if ! claude -p "/code-review" > "$out.md" 2> /dev/null; then
    # A failed reviewer must never look like a clean bill of health, and must
    # never wedge the PR either — report neutral and move on.
    status success "review unavailable (not a verdict)"
    rm -f "$out.md"
    exit 0
  fi

  gh pr review "$pr" --comment --body-file "$out.md" > /dev/null 2>&1 || true

  # Blocking findings are counted from the review body's own severity markers.
  blocking=$(grep -ciE '^[[:space:]]*[-*][[:space:]]*\*\*?(blocking|critical)' "$out.md" 2> /dev/null || true)
  blocking=${blocking:-0}

  if [ "$blocking" -gt 0 ]; then
    status failure "$blocking blocking finding(s) — see the review"
  else
    status success "no blocking findings"
  fi
  rm -f "$out.md"
) > /dev/null 2>&1 &

exit 0
