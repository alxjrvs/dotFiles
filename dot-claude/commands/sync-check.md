Verify that all dotfiles symlinks managed by ~/dotFiles/sync.sh are intact.

## Steps

1. Read `~/dotFiles/sync.sh` and extract every `link` call to build the full list of expected symlinks (source -> destination)
2. For each expected symlink, check:
   - Does the destination exist?
   - Is it a symlink (not a regular file or directory)?
   - Does it point to the correct source?
3. Report results in three categories:
   - **Correct** -- symlink exists and points to the right source
   - **Broken** -- symlink exists but target is missing, or points to the wrong source
   - **Missing** -- destination does not exist at all
   - **Conflict** -- a real file or directory exists at the destination instead of a symlink
4. For any issues found, suggest the exact fix (e.g., `ln -sfn <source> <destination>`, or `mv <file> <file>.bak && ln -sfn ...`)

## Notes

- The source of truth is the `link()` calls in `sync.sh`. Do not guess at symlinks.
- Some symlinks are conditional on OS (Darwin vs Linux) or gated behind `should_run` checks. Report all of them but note any that are platform-specific.
- Running `./sync.sh --only=symlinks` will fix most issues, but the point of this command is to audit without making changes.
