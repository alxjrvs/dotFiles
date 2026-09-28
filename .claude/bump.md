# dotFiles: the monthly bump

What a scheduled Routine runs here ("Follow .claude/bump.md"). It moves the pins nothing else
moves: the five linters in `mise.toml` and the two zsh plugins in `home/.chezmoiexternal.toml`.
Dependabot owns the workflow actions.

1. Take only a release at least 7 days old, the cooldown `dependabot.yml` keeps.
2. Linters: read the newest version and its date from where the web hook installs them (PyPI's
   JSON API for shellcheck-py and zizmor, the Go proxy's `@latest` for shfmt, actionlint and
   chezmoi). Bump each pin in `mise.toml` that moved, read its release notes, run
   `mise run lint`, and open one PR that names each bump. It merges on green like any other.
3. Externals: list tags with `git ls-remote --tags`. A newer tag needs its tarball's sha256, which
   a web session cannot download, so open an issue naming the tag, its changelog and the
   `curl … | shasum -a 256` line to run on the Mac. A person bumps them.
4. Nothing moved: say so and stop. No PR and no issue.
