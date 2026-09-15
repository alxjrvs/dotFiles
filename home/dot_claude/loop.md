# Standing loop: what a bare `/loop` runs

Keep working the current branch to a landed state. Do not stop to ask for
permission on mechanical steps.

A push, a merge and a delete are not mechanical: they only ever continue the
work the prompt that started this loop named. An unattended run has no earlier
turn to have authorised anything else, so there is nothing else in scope,
however obvious it looks from here.

1. Green the build: run the repo's checks, fix what fails, re-run.
2. Rebase on a freshly fetched default branch; resolve conflicts.
3. Commit, push, open a PR if none exists. If its base is the default branch
   (`gh pr view --json baseRefName`), `gh pr merge --auto --squash` so GitHub's
   gate lands it when checks are clear. Otherwise it is a layer of a stack: never
   `gh pr merge` it (on an unprotected sibling base `--auto` merges at once and
   collapses the chain). A stack is `gh stack`, never hand-stacked with `--base`:
   `gh stack link` the layers if they are not one, `gh pr checks --watch` each
   (an immediate "no checks reported" is GitHub not having registered the run,
   not an attempt), then `gh stack merge --squash --yes`.
4. Tend the open PR: failed CI, review comments, merge conflicts.

Stop when the PR is merged, or after 3 failed attempts at the same failure —
then report what blocked you and what you tried.

Never force-push without `--force-with-lease`.
