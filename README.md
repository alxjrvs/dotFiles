# dotFiles

macOS dotfiles for [alxjrvs](https://github.com/alxjrvs), managed by
[**boom**](https://github.com/alxjrvs/boom) — the small TypeScript dotfiles engine
extracted from this repo. This repo is pure *config*: a `boomfile.toml` and the payload
boom symlinks into place. The prompt is [starship](https://starship.rs); the Claude Code
statusline lives in [its own repo](https://github.com/TheGnarCo/claude-statusline).

Principles: [`CLAUDE.md`](CLAUDE.md#principles).

## Setup (fresh machine)

```bash
curl -fsSL https://raw.githubusercontent.com/alxjrvs/boom/v0.30.0/install.sh | sh
boom source set alxjrvs/dotFiles
```

The installer is pinned to a **tag, not `main`**. `install.sh` already verifies the binary
against the release's published `SHA256SUMS` and refuses to install unverified — so the
payload was never the exposed part. The script *fetching* it was: served from a mutable
branch, it could have been rewritten to drop those checks. A tag is immutable. Bump it when
`install.sh` itself changes; it still bootstraps the latest boom release.

Preview without touching anything: `boom source --dry-run`.

## Layout

```
boomfile.toml         the manifest — symlinks, packages, macOS defaults, verify steps
hooks/                boom lifecycle hooks (the directory name is boom's contract)
dot-claude/           user-global Claude config, symlinked into ~/.claude/
dot-claude/hooks/     Claude Code PreToolUse guards + their regression suites
git-template/hooks/   copied into every new repo via init.templateDir
scripts/              the assertions lefthook, CI and `boom verify` all share
zsh/ nvim/ ghostty/ ssh/ starship.toml …   payload
```

`boomfile.toml` names every payload file by path, so it is the manifest — read it there
rather than trusting a second copy here.

## Forking this repo

Ordered by what breaks first. Everything else is preference.

**1 — Identity, or your commits are signed as someone else.** Git name and email in
`.gitconfig` `[user]`; the agent identity in `dot-claude/settings.json` (`GIT_AUTHOR_EMAIL`,
`GIT_COMMITTER_EMAIL`, and the `attribution` trailers). Miss these and every commit an agent
makes on your machine is authored and co-signed as `alxjrvs`, silently, into public history.

**2 — 1Password, or `boom verify` fails on day one.** The service-account vault name in
`agent-vault.txt`; the `op://claude-agent/…` references in `dot-claude/settings.json` and
`npm/publish.env`; the SSH signing item at `boomfile.toml` `key = "GitHubSSH"` and in
`ssh/1password-agent.toml`. That last file scopes per *item*, not per vault — 1Password's
own least-privilege recommendation.

**3 — Org scope, which is a security control and not a preference.** `_owned_orgs()` in
`dot-claude/hooks/guard-lib.sh` is the single source deciding which repos an agent may write
to. On a fork it protects the wrong orgs until you change it.

**4 — Cosmetic.** The launchd labels in `launchd/`, the OTEL attribution in
`.claude/settings.json`, and the statusline source in `hooks/claude_statusline.ts`.

`scripts/identity-drift.sh` fails the build when the owner's name appears outside the set of
files that legitimately carry it.

## Where the reasoning lives

Beside the thing it explains: a guard's rationale is in its header, a gate's in its script,
the engine's in [boom](https://github.com/alxjrvs/boom). Decisions still in force that no
file already asserts are in [`dot-claude/DECISIONS.md`](dot-claude/DECISIONS.md), which is
not symlinked and so costs a session nothing.

MIT — see [`LICENSE`](LICENSE).
