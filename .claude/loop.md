# dotFiles: what a bare `/loop` runs here

Run the standing loop in `~/.claude/loop.md` — green the build, rebase, push,
open the PR, tend it — with the two facts that are this repo's own. It is named
rather than copied: a second copy with nothing keeping it equal is the drift
this repo exists to refuse.

1. A change here is only proven once it applies. From the worktree root, run
   `chezmoi apply --source "$PWD"` before opening the PR, and never pass
   `--init` with `--source`: the config template pins `sourceDir` to the working
   tree it was rendered from, and the app deletes that directory with the
   worktree.
2. `main` takes squash-merged pull requests with `lint` green and no bypass, so
   the completion path is `gh pr merge --auto --squash` and nothing else. Never
   push to `main`, and never merge into it locally.
