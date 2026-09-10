# dotFiles

macOS dotfiles for [alxjrvs](https://github.com/alxjrvs), managed by
[chezmoi](https://www.chezmoi.io). `home/` is the source state; the prompt is
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

`init --apply` clones this repo to `~/.local/share/chezmoi` and applies: files into `~`, then
the three `run_` scripts in [`home/`](home/): the Homebrew bundle (re-run when the Brewfile
changes), macOS defaults (re-run when they change), and an every-apply provision script (the
Claude Code CLI, `mise install`, gh extensions, the 1Password and GitHub MCP registrations).
Then `gh auth login` and a second `chezmoi apply` for the gh extensions.

Day to day: edit in the checkout (`chezmoi cd`), `chezmoi apply`, commit, PR. On another Mac,
`chezmoi update` pulls and applies what landed. Once per clone: `lefthook install`.

Two steps are by hand, once per machine, both into the login keychain with `-w` last so the
secret is prompted for and never on argv or in shell history. The agent's 1Password
service-account token, which `~/.local/bin/op-sa` reads:

```bash
security add-generic-password -a "$USER" -s op-claude-agent -w
```

And the agent's GitHub PAT, which git's `osxkeychain` helper reads under the account name pinned
in `home/dot_config/git/agent.gitconfig` (the name is only a keychain key). `-T` puts that helper
on the item's ACL, or macOS raises an access dialog on the first agent push and an unattended
session has no way to answer it; add `-U` when replacing a rotated token:

```bash
security add-internet-password -a claude-agent -s github.com -r htps \
  -T "$(git --exec-path)/git-credential-osxkeychain" -w
security add-internet-password -a claude-agent -s gist.github.com -r htps \
  -T "$(git --exec-path)/git-credential-osxkeychain" -w
```

Preview without touching anything: `chezmoi apply --dry-run --verbose`. Drift:
`scripts/verify.sh`, by hand. Upgrades are not chezmoi's job: `brew upgrade --formula`, then
`mise upgrade --bump` (commit the new pins).

## Layout

```
.chezmoiroot            "home" — the source state lives one directory down
home/                   what lands in ~  (dot_zshrc → ~/.zshrc, dot_config/… → ~/.config/…)
home/run_*              machine setup: brew (onchange), macOS defaults (onchange), provision (every apply)
home/dot_claude/        user-global Claude config: CLAUDE.md, settings.json, hooks, rules, skills
home/dot_claude/hooks/  two Claude Code hooks + their regression suites (suites are chezmoi-ignored)
home/.chezmoi*          chezmoi's own contract: ignore, externals
scripts/verify.sh       drift check, by hand
docs/GOTCHAS.md         traps still armed and the rule each forces; never applied to a machine
```

## Forking this repo

`git grep -ilE 'alxjrvs|claude-agent|GitHubSSH'` finds every file. In order of what breaks first: git identity and
signing key (`home/dot_gitconfig`, `home/private_dot_ssh/allowed_signers`), the agent identity
(`home/dot_claude/settings.json`), the `op://claude-agent/…` references (`settings.json`,
`home/run_after_50-provision.sh`, `npm/publish.env`), the SSH items in
`home/dot_config/1Password/ssh/agent.toml`, and the owned orgs in
`home/dot_claude/hooks/guard-lib.sh`, which decide where an agent may write.

## Where the reasoning lives

Beside the thing it explains: a hook's rationale is in its header, a run script's in its
comment block. Traps that no file asserts on its own are in [`docs/GOTCHAS.md`](docs/GOTCHAS.md);
history is in the PRs.

MIT — see [`LICENSE`](LICENSE).
