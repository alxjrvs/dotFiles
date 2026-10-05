---
name: bump
description: Move this repo's five linter pins in mise.toml to their newest week-old releases, in one PR. What the monthly Routine runs.
disable-model-invocation: true
---

# dotFiles: the monthly bump

What a scheduled Routine runs here (`/bump`). It moves the pins nothing else moves: the five
linters in `mise.toml`. Dependabot owns the workflow actions.

1. Take only a release at least 7 days old, the cooldown `dependabot.yml` keeps.
2. Bump each pin in `mise.toml` that moved. Versions come from the registries
   `.claude/hooks/session-start.sh` installs from: a web session's allowlist leaves out mise.run,
   and its GitHub proxy reaches only this repo, but raw.githubusercontent.com serves any public
   repo's files. Read each changelog there (`CHANGELOG.md` for shellcheck, shfmt and actionlint,
   `docs/release-notes.md` for zizmor); chezmoi's notes stay a link.
3. Re-run `.claude/hooks/session-start.sh`, which installs the bumped pins, then use the `verify`
   skill, and fix any new finding in the same change.
4. Open one PR that names each bump, links its release notes and states any breaking change. CI
   is the check, and `agent-auto-merge` decides whether it lands itself.
5. Nothing moved: say so and stop. No PR and no issue.
6. Anything above failed: open an issue titled `bump failed: <what>` saying why, through
   `gh api repos/{owner}/{repo}/issues -f title=… -f body=…`, the REST route the proxy allows. The
   upkeep-alert workflow mentions the owner on it, which reaches the phone.
