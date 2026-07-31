---
name: agent-friendly-repo
description: Make a GitHub repo agent-friendly for automated PR → auto-merge — squash-only merge settings, a single ruleset (linear history, non-fast-forward, one aggregate status check, no required human review, no bypass), stacked-PR support via the official `github/gh-stack` extension, and optionally a merge queue. Use when the user says "make this repo agent-friendly", "set up auto-merge", "align merge settings + branch protection", "add a merge queue", "set up stacked PRs", or bootstraps a repo and wants the agent completion path (`gh pr merge --auto`) to work. The executable version of the "Repository merge & branch-protection defaults" + "Agent worktree & merge workflow" sections in ~/.claude/CLAUDE.md.
---

# agent-friendly-repo

Turn a GitHub repo into one where the agent completion path — commit → push → PR → `gh pr merge --auto --squash` — actually lands, with **CI green for everyone** and **no human review gate** (agents can't approve their own PRs). Encodes the playbook worked out for `SalvageUnion-io/SU-SRD` (PR #393 + ruleset #9182849).

This mutates **outward-facing, shared-repo config**. Always read current state, print a proposed-changes diff, and **ask before mutating** — even under auto mode. Do the read + report unprompted; gate the writes.

## The checklist (what "agent-friendly" enforces)

**Repo merge settings** — `gh api repos/{o}/{r}`:
- `allow_squash_merge=true`, `allow_merge_commit=false`, `allow_rebase_merge=false` — squash-only.
- `allow_auto_merge=true` — **required** for `gh pr merge --auto`, the agent completion path. Without it, `--auto` errors.
- `delete_branch_on_merge=true` — GitHub deletes the remote branch server-side on merge, so agent worktree branches don't pile up (this is also the native fix for the #53 `--delete-branch` worktree-`main` collision — see CLAUDE.md).
- `allow_update_branch=true` — surfaces the "Update branch" button.
- `squash_merge_commit_title=PR_TITLE`, `squash_merge_commit_message=BLANK` (or `COMMIT_MESSAGES`) — clean squash subjects.

**Branch protection — ONE mechanism: a ruleset. Not classic + ruleset both.**
GitHub takes the **union** of classic protection and rulesets — a footgun, because editing one silently won't reflect in the other. Make the ruleset the single source of truth and **delete the redundant classic protection** once the ruleset supersets it.

Ruleset rules for the default branch:
- `required_linear_history`, `non_fast_forward`, `deletion` — block force-push and branch deletion, keep history linear.
- `required_status_checks` → a **single aggregate gate job** (e.g. `quality-checks`), not every individual job. An aggregate `if: always()` job that `needs:` every other job and fails if any *actually failed* (path-filtered "skipped" jobs are fine) avoids "required check stuck pending" when per-area jobs are path-filtered out of a given PR.
- **No required human PR reviews.** A required review blocks agent auto-merge forever — agents can't approve their own PRs. `--auto` waiting on green CI is the gate, not a human.
- `bypass_actors: []` — nobody bypasses, incl. admins → "CI green for everyone" (the standing preference). Agents don't need bypass; `--auto` just waits for green.

**Stacked PRs — the preferred shape for anything bigger than one reviewable change.**
Standing preference: split a large change into a stack of small PRs, each based on the one below
it, using the **official** `github/gh-stack` extension (public preview since 2026-07-30). The
dotFiles boomfile installs it (`gh extensions` section), so it should already be on the machine —
`gh extension install github/gh-stack` if not. Beware `gh ext search stack`: four community
extensions share the name, and only `github/gh-stack` is the one GitHub ships.

This checklist is already stack-compatible, and one item is *required* by stacks rather than
merely preferred:
- `required_linear_history` — `gh stack modify` refuses to restructure a stack whose history has
  merge commits or diverged branches, so linear history is a precondition, not a taste.
- `bypass_actors: []` — stack merges **cannot** bypass merge requirements at all (`gh stack merge`
  says so outright). A repo whose agent path depends on bypass simply can't use stacks.
- `allow_auto_merge=true` — auto-merge coexists with stacks: `gh stack unstack` deliberately
  leaves a PR stacked when it is queued or has auto-merge enabled.
- Squash-only is fine — `gh stack merge --squash` picks the method per-merge, *unless* a merge
  queue is in play (below), where the queue chooses and any method flag is ignored with a warning.

Stack-specific behavior worth knowing before recommending it:
- `gh stack merge [<stack#>|<pr#>]` merges every PR up to and including the named one as a
  **single all-or-nothing operation** — if any one can't merge, none do. Branch protection and
  rulesets are evaluated by GitHub when the merge runs, so a red aggregate check fails the whole
  batch, not just its layer.
- **With a merge queue**, the stack is *added to the queue* rather than merged directly, and the
  selected PRs "may land in separate groups rather than all at once" — so the all-or-nothing
  guarantee above does **not** hold behind a queue. Queue support for stacks was still rolling
  out at public preview; verify on the repo before promising it.
- Local stack state lives in `.git/gh-stack` (untracked), so it is per-clone — an agent worktree
  cut fresh does not inherit a stack. `gh stack checkout <stack#|pr#|url|branch>` re-attaches.
- `delete_branch_on_merge` + stacks: not verified here. `gh stack sync` prunes merged branches
  locally (`--prune` to skip the prompt); if a repo relies on server-side retargeting of child
  PRs, confirm it on that repo rather than assuming.

**Merge queue — the throughput unlock for parallel agents (optional, gated on CI support).**
`strict` required-status-checks (require-branch-up-to-date-before-merge) *serializes* parallel PRs: each merge marks every other open PR out-of-date → forced rebase + full CI re-run per PR. A **merge queue** removes that churn while preserving "tested against latest main" (it tests each PR against the merged result). See the sequencing hazard below — enabling it before CI handles `merge_group` hangs every PR.

## Procedure

1. **Resolve the repo + default branch.**
   ```
   o=$(gh repo view --json owner --jq .owner.login); r=$(gh repo view --json name --jq .name)
   def=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)
   ```

2. **Read current state** (all reads, no writes):
   ```
   gh api repos/$o/$r --jq '{allow_squash_merge,allow_merge_commit,allow_rebase_merge,allow_auto_merge,delete_branch_on_merge,allow_update_branch,squash_merge_commit_title,squash_merge_commit_message}'
   gh api repos/$o/$r/branches/$def/protection 2>/dev/null || echo "no classic protection"
   gh api repos/$o/$r/rulesets --jq '.[] | {id,name,target,enforcement}'
   # then for each ruleset id: gh api repos/$o/$r/rulesets/{id}
   gh api repos/$o/$r/commits/$def/check-runs --jq '.check_runs[].name' | sort -u   # real check names — no wildcard, must be exact
   ```

3. **Detect the aggregate gate job.** From the check-run names and the CI workflow(s) under `.github/workflows/`, find a single job that `needs:` the others with `if: always()`. If none exists, **recommend/scaffold one** — do NOT require every individual check (that leaves required checks stuck pending on path-filtered PRs). Scaffold shape:
   ```yaml
   quality-checks:
     if: always()
     needs: [lint, test, typecheck]      # every other job
     runs-on: ubuntu-latest
     steps:
       - name: Fail if any dependency failed
         if: contains(needs.*.result, 'failure') || contains(needs.*.result, 'cancelled')
         run: exit 1
   ```

4. **Diff against the checklist and print a proposed-changes report.** Group by: repo merge settings, ruleset (create/update/what rules), classic protection to delete, aggregate-gate action, merge-queue eligibility. Then **ask for confirmation** before any write.

5. **Apply merge settings** (one PATCH):
   ```
   gh api -X PATCH repos/$o/$r \
     -F allow_squash_merge=true -F allow_merge_commit=false -F allow_rebase_merge=false \
     -F allow_auto_merge=true -F delete_branch_on_merge=true -F allow_update_branch=true \
     -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=BLANK
   ```

6. **Create/update the ruleset** as the single source of truth. `~ref` for the default branch is `~DEFAULT_BRANCH`. Replace `<aggregate-check>` with the real name from step 3.
   ```
   gh api -X POST repos/$o/$r/rulesets --input - <<'EOF'
   {
     "name": "default-branch-protection",
     "target": "branch",
     "enforcement": "active",
     "bypass_actors": [],
     "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
     "rules": [
       { "type": "deletion" },
       { "type": "non_fast_forward" },
       { "type": "required_linear_history" },
       { "type": "required_status_checks",
         "parameters": {
           "strict_required_status_checks_policy": true,
           "required_status_checks": [ { "context": "<aggregate-check>" } ]
         } }
     ]
   }
   EOF
   ```
   To update an existing ruleset instead, `gh api -X PUT repos/$o/$r/rulesets/{id} --input -` with the same body.

7. **Delete the redundant classic protection** — only *after* confirming the ruleset supersets it:
   ```
   gh api -X DELETE repos/$o/$r/branches/$def/protection
   ```

8. **Merge queue (optional, only if the user wants it).** Follow the sequencing hazard below.

9. **Report** the final state: merge settings, ruleset id + rules, whether classic was removed, aggregate-gate action taken, queue enabled or deferred (and why), and **stack readiness** — `gh extension list | grep github/gh-stack` for the tool, plus whether `required_linear_history` and empty `bypass_actors` hold (the two rules stacks actually require).

## Critical sequencing hazard — merge queue

Enabling the queue before CI reports on the queue's temp branches **hangs every PR forever**. Enforce this order:

1. **Land the CI `merge_group:` trigger on `main` FIRST**, via a normal PR under current rules. Add `merge_group:` to the workflow's `on:` so the aggregate check reports on the queue's temp branches. Also force-enable path-filtered jobs on `merge_group` (they have no diff base there — the queue is the final gate before main), e.g. a `changes` job that outputs "all areas changed" when `github.event_name == 'merge_group'`.
2. **Only after that's merged to `main`:** add the `merge_queue` rule to the ruleset **and** set `strict_required_status_checks_policy: false` (the queue supersedes strict; GitHub disallows strict alongside a queue). Add `{ "type": "merge_queue", "parameters": { ... } }` to the ruleset `rules` and flip the strict flag in the `required_status_checks` rule.

Then agents complete with `gh pr merge --auto --squash`, which adds the PR to the queue; the queue tests it against the merged result and lands it when green.

## Guardrails

- **Ask before every mutation.** Reads and the diff report are unprompted; writes are gated. This is shared-repo config.
- **Never require a human review** and never leave `bypass_actors` non-empty for "convenience" — both defeat the agent path. If the user *wants* human review on a repo, that repo isn't a candidate for unattended auto-merge; say so rather than half-configuring it.
- **`enforce_admins`/no-bypass = CI green for everyone, including alxjrvs.** For a genuine one-off emergency, disable+re-enable rather than weakening the default (delete the ruleset temporarily, or from a plain terminal). Don't add a standing bypass.
- **Aggregate gate, not per-check requirements.** Requiring individual path-filtered jobs strands required checks in "pending". If you can't find/scaffold an aggregate job, stop and surface that — don't require the individual jobs as a fallback.
- **Merge queue is opt-in and CI-gated.** Never add the `merge_queue` rule before the `merge_group:` trigger is on `main`. If CI has no `merge_group:` trigger, do the CI PR first (or defer the queue) — never enable it speculatively.
- **Only `github/gh-stack`.** Never install a same-named community fork to satisfy "stacked PRs"; if the official extension is missing, install it or say so — don't substitute.
- **Stacks are a workflow preference, not a repo mutation.** Nothing in this skill's write path enables them. Recommending stacks costs the repo nothing; the only repo-side facts are that `required_linear_history` and empty `bypass_actors` are prerequisites, and both are already on the checklist.
- **Reference target:** SU-SRD PR #393 (the `merge_group` CI trigger + `changes` path-filter handling) and SU-SRD ruleset #9182849 are a known-good "after" state.
