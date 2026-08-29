# What "agent-friendly" enforces — the full checklist

Reference for the `agent-friendly-repo` skill. Split out of SKILL.md because it is
a settings INVENTORY, and most invocations touch one branch of it: a repo that needs
auto-merge aligned does not need the merge-queue reasoning, and one adding stacked PRs
does not need the Dependabot lane. A skill body loads in full whenever the skill
fires, so all of it was charged for whichever slice was actually wanted.

The procedure in SKILL.md says when to read this.

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

**`.worktreeinclude` — the gitignored files an agent worktree needs.**
The one repo-local file on this checklist rather than a GitHub setting. A worktree is a fresh
checkout, so `.env`, `.env.local` and any other gitignored config are simply absent, and the
agent's first command fails against a repo that cannot boot. Claude Code copies gitignored files
matching a `.worktreeinclude` at the repo root into every worktree it creates — `--worktree`,
subagent (`isolation: worktree`) worktrees, and desktop parallel sessions. `.gitignore` syntax,
and a pattern only copies a file that is **also** gitignored, so tracked files are never
duplicated.

```text
.env
.env.local
config/secrets.json
```

- **Never hand-roll this as a SessionStart hook.** The built-in covers every worktree Claude Code
  creates; a hook cannot. `SubagentStart` carries the parent process's cwd rather than the
  subagent's worktree (see DECISIONS.md), so `isolation: worktree` subagents — the ones that churn
  most — would keep starting without their env files.
- **It copies, it does not link** — a plaintext secret in `.env` becomes one more copy on disk per
  worktree. A repo whose `.env` holds `op://` references costs nothing here; one holding live
  tokens is the argument for converting it, not for skipping the file.
- **A `WorktreeCreate` hook replaces the built-in git path entirely**, and `.worktreeinclude` is
  not processed then — a repo on a non-git VCS copies the files inside that hook instead.
- Only worth adding where the repo actually has gitignored files a build needs. This repo
  (dotFiles) has none, so it deliberately carries no `.worktreeinclude`.

**Stacked PRs — the preferred shape for anything bigger than one reviewable change.**
Standing preference: split a large change into a stack of small PRs, each based on the one below
it, using the **official** `github/gh-stack` extension (public preview since 2026-07-30). The
dotFiles boomfile installs it (`gh extensions` section), so it should already be on the machine —
`gh extension install github/gh-stack` if not. Beware `gh ext search stack`: four community
extensions share the name, and only `github/gh-stack` is the one GitHub ships.

This checklist is already stack-compatible, and **two of its items turn out to be preconditions**
for stacks rather than merely preferred:
- `required_linear_history` — **precondition.** `gh stack modify` refuses to restructure a stack
  whose history has merge commits or diverged branches, so linear history is not a taste here.
- `bypass_actors: []` — **precondition, from the other direction.** Stack merges **cannot** bypass
  merge requirements at all (`gh stack merge` says so outright), so a repo whose agent path
  depends on a bypass actor simply can't use stacks.
- `allow_auto_merge=true` — **required for the ordinary path, but it cannot land a stack.**
  GitHub's docs say it outright: "Auto-merge is not supported for stacked pull requests." A stack
  lands only through the Stacks API — "the legacy pull request merge endpoints can't merge a
  stack" — which is the endpoint `gh pr merge` calls. (`gh stack unstack`'s note that GitHub
  "leaves stacked" a PR that is queued or has auto-merge enabled describes GitHub refusing to
  *unstack* a PR with a pending merge intent. It is not evidence of an unattended completion
  path, and reading it as one was this checklist's earlier error.)
- **No merge queue — that is the house default, and it is a decision, not an omission.** A queue
  is the only fire-and-forget path for a stack (`gh stack merge` *enqueues*, the queue lands it
  when green). It was declined because it is mutually exclusive with the Dependabot auto-merge
  workflow — `GITHUB_TOKEN` cannot add a PR to a queue — and because it carries the
  `merge_group:` sequencing hazard below. The accepted cost is that `gh stack merge` does **not**
  wait: it checks only that each PR is open and non-draft, then asks GitHub to merge *now*, and a
  red or pending check fails the entire all-or-nothing batch. So the supported flow is
  **watch every layer green (`gh pr checks <pr> --watch`), then merge** — see `ship`. Do not
  recommend a queue as the remedy for that wait; recommend it only if a repo has no Dependabot
  auto-merge to lose *and* the user asks.
- Squash-only is fine — `gh stack merge --squash` gives one squashed commit per layer, which is
  what preserves the layering in a linear history. (A queue, if one ever exists, picks the method
  itself and ignores the flag with a warning.)

Stack-specific behavior worth knowing before recommending it:
- `gh stack merge [<stack#>|<pr#>]` merges every PR up to and including the named one as a
  **single all-or-nothing operation** — if any one can't merge, none do. Branch protection and
  rulesets are evaluated by GitHub when the merge runs, so a red aggregate check fails the whole
  batch, not just its layer.
- **With a merge queue**, the stack is *added to the queue* rather than merged directly, and the
  selected PRs "may land in separate groups rather than all at once" — so the all-or-nothing
  guarantee above does **not** hold behind a queue. Queue support is otherwise complete, not
  partial: "Stacks fully support merge queues. All pull requests in the stack are added to the
  queue in the correct order." Two behaviors follow from that and are worth knowing before
  sizing a stack — the queue "allows the merge group to exceed its configured maximum size by up
  to 50 percent" to keep a stack together, and splits a stack that still doesn't fit across
  consecutive merge groups; and "if a pull request is removed or ejected from the queue, all
  pull requests above it in the stack are also removed", so one flaky layer ejects everything
  above it.
- Checks are enforced **per PR, against the stack's base branch**, not just on the bottom PR:
  merging PR #3 of `main ← #1 ← #2 ← #3` requires #1 and #2 to satisfy the base branch's required
  status checks, required reviews, and CODEOWNERS too. So the default-branch ruleset does govern
  the whole stack — an intermediate PR is not an unguarded hole — and equally, a required human
  review is fatal to *every* layer, not just the last.
- Local stack state lives in `.git/gh-stack` (untracked), so it is per-clone — an agent worktree
  cut fresh does not inherit a stack. `gh stack checkout <stack#|pr#|url|branch>` re-attaches.
- `delete_branch_on_merge` + stacks: not verified here. `gh stack sync` prunes merged branches
  locally (`--prune` to skip the prompt); if a repo relies on server-side retargeting of child
  PRs, confirm it on that repo rather than assuming.

**Dependabot auto-merge — the same completion path, for the bot (optional).**
This checklist already removes the only real blocker: **no required human review** means a
Dependabot PR needs nothing but a green aggregate check. But there is **no native switch** —
`dependabot.yml` has no automerge key (Renovate does; Dependabot doesn't) and the per-PR
auto-merge button needs a human click. The mechanism is one small workflow that calls
`gh pr merge --auto` on Dependabot's PRs; GitHub's own gate does the waiting.

```yaml
name: dependabot-auto-merge
on: pull_request                    # NOT pull_request_target — see below
permissions:
  contents: write
  pull-requests: write
jobs:
  auto-merge:
    if: github.actor == 'dependabot[bot]'
    runs-on: ubuntu-latest
    steps:
      - uses: dependabot/fetch-metadata@v2
        id: meta
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
      - name: Enable auto-merge (minor + patch only)
        if: >-
          steps.meta.outputs.update-type == 'version-update:semver-minor' ||
          steps.meta.outputs.update-type == 'version-update:semver-patch'
        run: gh pr merge --auto --squash "$PR_URL"
        env:
          PR_URL: ${{ github.event.pull_request.html_url }}
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

Four things that decide whether this works on a given repo:
- **`on: pull_request`, not `pull_request_target`.** Dependabot-triggered runs get a read-only
  `GITHUB_TOKEN` *by default*, but have respected the `permissions:` key since Oct 2021, so plain
  `pull_request` is sufficient. `pull_request_target` runs with a write token in base-branch
  context — unnecessary risk for a job that never checks out PR code.
- **Actions secrets are unavailable to Dependabot-triggered runs** (only *Dependabot* secrets
  are). If the aggregate gate job needs a secret, it fails on every Dependabot PR and auto-merge
  simply never fires. Check this before promising it — a hermetic CI is a precondition.
- **A merge queue breaks it.** `GITHUB_TOKEN` **cannot add a PR to a merge queue**; that needs a
  PAT or GitHub App token. So the merge-queue step and this step conflict — surface the choice
  rather than configuring both and leaving Dependabot PRs stuck queued-but-never-added.
- **A `GITHUB_TOKEN` merge triggers no downstream workflows.** A `push:`-on-default-branch job
  won't run for these merges. Harmless (the PR was already gated), but not invisible.

Gate on an **allowlist** (`== minor || == patch`), never a denylist (`!= major`): if
`update-type` ever comes back empty, a denylist auto-merges it. Pair with a `dependabot.yml`
group scoped to `update-types: ["minor", "patch"]` so majors arrive as separate manual PRs.
`update-type` is documented as "the highest semver change being made by this PR", so it holds for
grouped PRs too.

**Merge queue — the throughput unlock for parallel agents (optional, gated on CI support).**
`strict` required-status-checks (require-branch-up-to-date-before-merge) *serializes* parallel PRs: each merge marks every other open PR out-of-date → forced rebase + full CI re-run per PR. A **merge queue** removes that churn while preserving "tested against latest main" (it tests each PR against the merged result). See the sequencing hazard below — enabling it before CI handles `merge_group` hangs every PR.

