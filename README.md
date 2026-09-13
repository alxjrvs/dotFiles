# dotFiles

macOS and Linux dotfiles for [alxjrvs](https://github.com/alxjrvs), managed by
[chezmoi](https://www.chezmoi.io). `home/` is the source state. Principles:
[`CLAUDE.md`](CLAUDE.md#principles).

## Fresh machine

Two lines, the second of which is a login:

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin init --apply --source ~/Code/dotFiles alxjrvs/dotFiles
gh auth login && chezmoi apply
```

The first apply asks for a password once (Homebrew's installer, on a Mac); what waits on
`gh auth login` converges on the second. An ephemeral container (a Claude Code cloud
environment's setup script) takes one line and leaves nothing behind; a devcontainer points VS
Code's `dotfiles.repository` at this repo, which runs [`install.sh`](install.sh).

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --one-shot alxjrvs/dotFiles
```

## Day to day

| | |
|---|---|
| change something | edit the checkout, `chezmoi apply`, commit, PR |
| drift | `chezmoi verify` |
| upgrade | `mise upgrade`, `chezmoi upgrade`, `brew upgrade --cask <app>`; apply never upgrades |
| another machine | `chezmoi update` |
| the config template changed | `chezmoi apply --init` |
| the repo settings | [`.github/gate.sh`](.github/gate.sh), once, by the owner |

GitHub is the gate: `main` takes squash-merged pull requests with the `lint` check green, and
push protection stops a secret before it lands. The agent is you: `gh auth login` is the one
credential, `gh` the one tool, git borrows the token, and the squash-merged PR is the record.

## Layout

```
.chezmoiroot            "home": the source state lives one directory down
.github/gate.sh         the repo settings that are not files: ruleset, scanning, merge policy
install.sh              chezmoi's generated devcontainer hook
home/                   what lands in ~  (dot_zshrc → ~/.zshrc, dot_config/… → ~/.config/…)
home/.chezmoiscripts/   machine setup: Homebrew and its apps (Mac), mise with every CLI (both), macOS defaults, provisioning, Caps Lock
home/dot_claude/        user-global Claude Code config
home/.chezmoi*          chezmoi's own contract: config template, version floor, ignores, externals
docs/GOTCHAS.md         traps still armed and the rule each forces
```

## Forking

`git grep -ilE 'alxjrvs|GitHubSSH'` finds every file to change: git identity and signing key,
the marketplace and plugin, the SSH items, the launchd label, and the persona. Then
`.github/gate.sh`.

MIT — see [`LICENSE`](LICENSE).
