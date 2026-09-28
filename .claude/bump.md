# dotFiles: the monthly bump

What a scheduled Routine runs here ("Follow .claude/bump.md"). It moves the pins nothing else
moves: the five linters in `mise.toml`. Dependabot owns the workflow actions; Homebrew's nightly
upgrade owns the zsh plugins.

1. Take only a release at least 7 days old, the cooldown `dependabot.yml` keeps.
2. Linters: read the newest version and its date from where the web hook installs them (PyPI's
   JSON API for shellcheck-py and zizmor, the Go proxy's `@latest` for shfmt, actionlint and
   chezmoi). Bump each pin in `mise.toml` that moved, read its release notes (its changelog through
   raw.githubusercontent.com; chezmoi's live only on GitHub release pages, which a web session
   cannot open, so link them), and open one PR that names each bump, then
   `gh pr merge --auto --squash` it. CI is its check: in the session, `mise run lint` still runs
   the pre-bump binaries.
3. Nothing moved: say so and stop. No PR and no issue.
4. Anything above failed: open an issue titled `bump failed` with what failed and why. The
   upkeep-alert workflow mentions the owner on it, which reaches the phone.
