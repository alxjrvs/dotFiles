---
name: agent-friendly-repo
description: Configure a GitHub repo for automated PR → auto-merge: squash-only merges, a branch-protection ruleset, stacked PRs via the official github/gh-stack, and optional Dependabot auto-merge or merge queue. Use for "make this repo agent-friendly", "set up auto-merge", "align merge settings + branch protection", "add a merge queue", "set up stacked PRs", "auto-merge dependabot", "carry .env into worktrees".
disable-model-invocation: true
---

# agent-friendly-repo

Turn a GitHub repo into one where the agent completion path — commit → push → PR → `gh pr merge --auto --squash` — actually lands, with **CI green for everyone** and **no human review gate** (agents can't approve their own PRs). Encodes the playbook worked out for `SalvageUnion-io/SU-SRD` (PR #393 + ruleset #9182849).

This mutates **outward-facing, shared-repo config**. Always read current state, print a proposed-changes diff, and **ask before mutating** — even under auto mode. Do the read + report unprompted; gate the writes.

**The full checklist — every setting this enforces, the ruleset JSON, and the optional Dependabot and merge-queue branches — is in [`references/checklist.md`](references/checklist.md).** Read the slice the request actually needs. It is separate because most invocations touch one branch of it: aligning auto-merge does not need the merge-queue reasoning, and adding stacked PRs does not need the Dependabot lane, but a skill body loads in full every time the skill fires.

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

8. **Merge queue — skip by default.** The standing decision is no queue: it would cost the
   Dependabot auto-merge path (`GITHUB_TOKEN` can't enqueue), and stacks land fine by watching
   them green and merging directly. Only do this step if the user explicitly asks *and* the repo
   has no Dependabot auto-merge to lose — then follow the sequencing hazard below. Don't offer it
   as the cure for "the agent has to wait for CI"; that wait is the accepted trade.

9. **Dependabot auto-merge (optional, only if the user wants it).** Confirm the repo actually has
   a `.github/dependabot.yml` (if not, that's the first question — which ecosystems), that the
   aggregate gate job needs no Actions secrets, and that no merge queue is enabled. Then add the
   workflow above plus a minor/patch group, and **ask for the update-type ceiling** rather than
   assuming it — `github-actions` bumps in particular change code that runs against a
   write-scoped token.

10. **Report** the final state: merge settings, ruleset id + rules, whether classic was removed, aggregate-gate action taken, queue enabled or deferred (and why), whether a `.worktreeinclude` covers the repo's gitignored env files, and **stack readiness** — `gh extension list | grep github/gh-stack` for the tool, whether `required_linear_history` and empty `bypass_actors` hold (the two rules stacks actually require), and that the landing path is watch-then-`gh stack merge` (no queue, by standing decision). If a queue *is* already configured on the repo, say so — it changes the merge semantics (enqueue instead of merge-now, method flags ignored, large stacks split across groups).

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
- **Dependabot auto-merge is opt-in, allowlisted, and queue-incompatible.** Never gate it with
  `!= major` (fails open on an empty `update-type`), never enable it on a repo whose CI needs
  Actions secrets (they're unavailable to Dependabot runs, so it silently never fires), and never
  configure it alongside a merge queue without swapping `GITHUB_TOKEN` for a PAT/App token —
  `GITHUB_TOKEN` cannot add a PR to a queue.
- **Never hand-roll worktree env-copying.** `.worktreeinclude` is the built-in; a SessionStart
  hook that copies or symlinks `.env` into worktrees is custom code for a feature that ships, and
  it runs too late for the agent's first turn anyway.
- **Only `github/gh-stack`.** Never install a same-named community fork to satisfy "stacked PRs"; if the official extension is missing, install it or say so — don't substitute.
- **Stacks cost the repo nothing to enable.** `required_linear_history` and empty `bypass_actors` are their only prerequisites, and both are already on the checklist. There is no repo mutation to make stacks work — landing them is a *workflow* (watch green, then `gh stack merge`), which is why the queue is skippable.
- **Never claim auto-merge works on a stack.** It does not — GitHub says so explicitly, and the legacy merge endpoint `gh pr merge` calls cannot merge a stack at all. The correct answer to "how does a stack land unattended, then" is: the agent watches every layer to green and runs `gh stack merge`, per the `ship` skill. It is not "add a merge queue."
- **Reference target:** SU-SRD PR #393 (the `merge_group` CI trigger + `changes` path-filter handling) and SU-SRD ruleset #9182849 are a known-good "after" state.
