# dotFiles

macOS dotfiles for [alxjrvs](https://github.com/alxjrvs), managed by
[chezmoi](https://www.chezmoi.io) in symlink mode. `home/` is the source state; the prompt is
[starship](https://starship.rs); the Claude Code statusline lives in
[its own repo](https://github.com/TheGnarCo/claude-statusline) and arrives as two pinned
chezmoi externals straight onto PATH.

Principles: [`CLAUDE.md`](CLAUDE.md#principles).

## Setup (fresh machine)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install chezmoi
chezmoi init --apply alxjrvs/dotFiles
```

`init --apply` clones this repo to `~/.local/share/chezmoi`, renders `~/.config/chezmoi/chezmoi.toml`
from [`home/.chezmoi.toml.tmpl`](home/.chezmoi.toml.tmpl), and applies: symlinks into `~`, then
the `run_` scripts in [`home/`](home/) — the Claude Code CLI, Homebrew bundle, `mise install`,
gh extensions, macOS defaults, LaunchAgents, lefthook, tldr, the 1Password and GitHub MCP
registrations — each darwin-gated and either hashed on the file it applies or cheap enough to
run every time.

Two steps are by hand, once per machine, both into the login keychain with `-w` last so the
secret is prompted for and never on argv or in shell history. The agent's 1Password
service-account token, which `~/.local/bin/op-sa` reads:

```bash
security add-generic-password -a "$USER" -s op-claude-agent -w
```

And the agent's GitHub PAT, which git's `osxkeychain` helper reads under the account name pinned
in `home/dot_config/git/agent.gitconfig` (the name is only a keychain key). `-T` puts that helper
on the item's ACL, or macOS raises an access dialog on the first agent push; add `-U` when
replacing a rotated token:

```bash
security add-internet-password -a claude-agent -s github.com -r htps \
  -T "$(git --exec-path)/git-credential-osxkeychain" -w
security add-internet-password -a claude-agent -s gist.github.com -r htps \
  -T "$(git --exec-path)/git-credential-osxkeychain" -w
```

To work from an existing checkout instead of the managed clone, point chezmoi at it once:
`chezmoi init --source <your checkout> --apply`. The config template records `sourceDir`, so
there is one clone and an edit here is live immediately. Then `gh auth login` and a second
`chezmoi apply`: the gh-extensions script skips politely until gh is authenticated.

Preview without touching anything: `chezmoi apply --dry-run --verbose`. Drift:
`scripts/verify.sh`, which the `com.alxjrvs.dotfiles-verify` LaunchAgent runs daily and which
notifies on failure. Upgrades are not chezmoi's job: `brew upgrade --formula`, then
`mise upgrade` (commit `mise.lock`).

## Layout

```
.chezmoiroot            "home" — the source state lives one directory down
home/                   what lands in ~  (dot_zshrc → ~/.zshrc, dot_config/… → ~/.config/…)
home/run_*.sh.tmpl      machine setup, in the order chezmoi runs them (before → files → after)
home/dot_claude/        user-global Claude config: CLAUDE.md, settings.json, hooks, rules, skills, agents
home/dot_claude/hooks/  Claude Code guards + their regression suites (suites are chezmoi-ignored)
home/.chezmoi*          chezmoi's own contract: config template, ignore, remove, externals
scripts/                the assertions lefthook, CI and verify.sh share; verify.sh itself
docs/DECISIONS.md       reasons, incidents, measurements — never symlinked, so it costs nothing
```

## Forking this repo

Ordered by what breaks first. Everything else is preference.

**1 — Identity, or your commits are signed as someone else.** Git name and email in
`home/dot_gitconfig` `[user]`; the agent identity in `home/dot_claude/settings.json`
(`GIT_AUTHOR_EMAIL`, `GIT_COMMITTER_EMAIL`, and the `attribution` trailers). Miss these and
every commit an agent makes on your machine is authored and co-signed as `alxjrvs`, silently,
into public history.

**2 — 1Password, or `verify.sh` fails on day one.** The `op://claude-agent/…` references in
`home/dot_claude/settings.json`, `home/run_after_81-github-mcp.sh.tmpl` and `npm/publish.env`;
the two keychain items above; the `user.signingkey` in `home/dot_gitconfig` and the matching
line in `home/private_dot_ssh/allowed_signers`; the SSH items named in
`home/dot_config/1Password/ssh/agent.toml`. That last file scopes per *item*, not per vault —
1Password's own least-privilege recommendation.

**3 — Org scope, which is a security control and not a preference.** `_owned_orgs()` in
`home/dot_claude/hooks/guard-lib.sh` is the single source deciding which repos an agent may
write to. On a fork it protects the wrong orgs until you change it.

**4 — Cosmetic.** The launchd labels under `home/Library/LaunchAgents/` and the `# alxjrvs`
heading in `home/dot_claude/CLAUDE.md`.

Nothing enforces this list. `git grep -il alxjrvs` is the check, and forking is a once-ever event.

## Where the reasoning lives

Beside the thing it explains: a guard's rationale is in its header, a gate's in its script, a
run script's in its comment block. Decisions still in force that no file already asserts are in
[`docs/DECISIONS.md`](docs/DECISIONS.md), which is outside `home/` and so costs a session nothing.

MIT — see [`LICENSE`](LICENSE).
