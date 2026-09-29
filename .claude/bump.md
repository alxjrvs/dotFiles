# dotFiles: the monthly bump

What a scheduled Routine runs here ("Follow .claude/bump.md"). It moves the pins nothing else
moves: the five linters in `mise.toml`. Dependabot owns the workflow actions; Homebrew's nightly
upgrade owns the zsh plugins.

1. Take only a release at least 7 days old, the cooldown `dependabot.yml` keeps.
2. Bump each pin in `mise.toml` that moved and open one PR that names each bump and links its
   release notes, then `gh pr merge --auto --squash` it. A web session's proxy blocks GitHub, so
   versions come from the registries `.claude/hooks/session-start.sh` installs from, and a
   changelog that lives only on GitHub is linked, not read. CI is the check: in the session,
   `mise run lint` still runs the pre-bump binaries.
3. Nothing moved: say so and stop. No PR and no issue.
4. Anything above failed: open an issue titled `bump failed` with what failed and why. The
   upkeep-alert workflow mentions the owner on it, which reaches the phone.
