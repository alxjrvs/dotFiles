---
name: ship
description: Ship the current worktree — verify, commit, rebase, push, open a PR, and enable auto-merge — in one step, with a separate stack-aware path (`gh stack sync`/`submit`/`merge`) when the branch is part of a stacked PR. Use when work is done and the user says "ship it", "commit + push + PR", "open a PR and auto-merge", "land the stack", or otherwise asks to land the branch. Encodes alxjrvs's standard completion pipeline so it never has to be re-typed.
---

# ship

The completion pipeline for a finished piece of work: **verify → commit → rebase → push → PR → auto-merge**. This is alxjrvs's documented standard (see `~/.claude/CLAUDE.md`, "Agent worktree & merge workflow"); running it as one skill replaces re-typing the steps every time.

Never run this on `main`/`master` directly — the rebase-guard hook denies a direct push to the default branch, and that is correct. You must be on a feature branch in a worktree.

## First: is this branch in a stack?

Run `gh stack view` before anything else. If it reports a stack containing the current branch, **the steps below are the wrong pipeline** — jump to *Shipping a stack*. Getting this wrong is not cosmetic: a stacked PR's base is the branch below it, so `gh pr merge --auto --squash` would merge this layer **into its parent branch**, not into `main`, and silently collapse the stack.

`gh stack view` exiting non-zero (or reporting no stack) means the ordinary path applies. Note that stack state lives in `.git/gh-stack`, which is untracked and per-clone — a freshly cut agent worktree never inherits one, so a branch that *is* part of a stack on GitHub can still look unstacked locally. If the branch was created by `gh stack add`, or the user has been talking about a stack, re-attach with `gh stack checkout <stack#|pr#|url|branch>` before deciding.

## Steps

1. **Verify the change actually works.** Invoke the `verify` skill (or the repo's own check command — `bun run check:all`, `bun test`, `mise run ci`, etc.). Drive the affected flow, don't just typecheck. If verification fails, STOP and report — do not ship broken work.

2. **Stage and commit.** `git add -A` (or the specific paths), then a Conventional-Commit message (`feat:`/`fix:`/`chore:`/`docs:`…). The commit trailers (`Co-Authored-By`, `Claude-Session`) are appended by config — don't hand-add them. If there are already commits on the branch and only small fixups remain, amend or add a focused commit rather than one giant blob.

3. **Rebase onto the fresh target** *before pushing* — this keeps the rebase-guard a silent no-op:
   ```
   git fetch origin && git rebase origin/HEAD
   ```
   Resolve conflicts with full context if any. (`origin/HEAD` resolves to the default branch; use `origin/main` if it isn't set.)

4. **Push** the branch, force-with-lease if it was pushed before:
   ```
   git push -u origin HEAD          # first push
   git push --force-with-lease      # after a rebase of an already-pushed branch
   ```

5. **Open a draft PR** (unless the user asked for a ready one). Title mirrors the commit; body summarizes what changed and how it was verified, ending with the standard generated-with trailer:
   ```
   gh pr create --draft --fill
   ```

6. **Enable auto-merge** so GitHub's gated queue lands it once required checks pass (this is why the `Bash(gh pr merge:*)` permission rule exists):
   ```
   gh pr merge --auto --squash
   ```
   Squash matches the repo default. **Do not add `-d`/`--delete-branch`** — that caused the #53 worktree-`main` collision (`gh` checks out `main` to delete the local branch, which the primary checkout already holds). The repos enable `delete_branch_on_merge`, so GitHub deletes the remote branch server-side; if a target repo doesn't, delete it manually *after* confirming the PR merged (`gh pr view --json state`), never right after an `--auto` merge on a not-yet-green PR. `--auto` waits for CI — it does **not** bypass required checks, and it is never a local `git merge`/`git push` onto `main`.

## Shipping a stack

Same first two steps — **verify** (step 1) and **commit** (step 2) on the current layer — then `gh stack` owns the rest, because it does the cascading rebase across every branch that steps 3–4 do for one:

3. **Sync the stack**: `gh stack sync`. This fetches, fast-forwards trunk, cascade-rebases each branch onto its updated parent, and pushes them atomically (`--force-with-lease --atomic`). It is the stack-shaped form of the rebase-before-push rule — and it matters that you run it, because the rebase-guard tokenizes for `git push` / `gh pr create` and so **never fires on any `gh stack` command**. Nothing will stop you publishing a stale stack. If it reports a rebase conflict it restores every branch and tells you to run `gh stack rebase`; resolve there, don't force past it.

4. **Submit**: `gh stack submit` pushes the branches and creates/updates one PR per branch, each based on the one below, then links them into a stack on GitHub. Non-interactively (or with `--auto`) it uses generated titles and creates PRs as **drafts** unless you pass `--open` — so for a stack meant to be reviewed, either write the titles interactively or pass `--open` deliberately.

5. **Land it — and this is where the ordinary pipeline does not transfer.** `gh pr merge --auto` **cannot merge a stack**: GitHub's docs state "Auto-merge is not supported for stacked pull requests", and the legacy merge endpoint `gh pr merge` calls can't merge a stack at all. Use the Stacks API via `gh stack merge [<stack#>|<pr#>] --yes --squash`, which merges every PR up to and including the named one all-or-nothing.

   Which mode you're in depends on the repo:
   - **Merge queue configured** → `gh stack merge` *enqueues* the stack and the queue lands it once checks pass. This is the only fire-and-forget path for a stack, and the closest analogue to `--auto`. The queue picks the merge method, so `--squash` is ignored with a warning; large stacks may be split across consecutive merge groups, so the all-or-nothing guarantee weakens to per-group.
   - **No merge queue** → `gh stack merge` asks GitHub to merge **now**. It only checks that each PR is open and non-draft; GitHub evaluates the rules at merge time, so a red or still-pending aggregate check fails the whole batch. **Do not run it speculatively on an unattended job.** Either stop after step 4 and report the stack for a human to land, or — if the user explicitly asked you to see it through — wait for checks (`gh pr checks <bottom-pr> --watch`) and merge once green.

   Either way, never try to fake `--auto` by enabling auto-merge on the bottom PR and calling it done: that lands one layer into `main` and leaves the rest of the stack rebasing behind it.

## Guardrails

- If required checks aren't configured on the repo, `--auto` may merge immediately — confirm the repo has branch protection before relying on it for unattended jobs.
- **Check for a stack first, every time.** `gh pr merge --auto --squash` on a stacked PR merges it into its parent branch, not the default branch. This is the single most damaging way to misuse this skill.
- **A stack on a queue-less repo has no unattended completion path.** Say so and hand back the stack rather than blocking on a wait loop or merging something that isn't green. If the user wants stacks to land unattended on that repo, the fix is the `agent-friendly-repo` skill's merge-queue step, not a workaround here.
- If the user said "don't auto-merge" (they sometimes want to land something ahead of this branch), stop after step 5 and report the PR URL.
- Report the PR URL and the final state (draft/ready, auto-merge enabled) when done.
