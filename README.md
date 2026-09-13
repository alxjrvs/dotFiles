# dotFiles

macOS and Linux dotfiles for [alxjrvs](https://github.com/alxjrvs), managed by
[chezmoi](https://www.chezmoi.io). `home/` is the source state. Principles:
[`CLAUDE.md`](CLAUDE.md#principles).

## Fresh machine

A Mac or a Linux box, in two lines, the second of which is a login:

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin init --apply --source ~/Code/dotFiles alxjrvs/dotFiles
gh auth login && chezmoi apply
```

The first line installs chezmoi into `~/.local/bin` (`chezmoi upgrade` maintains it), clones
into `~/Code/dotFiles`, renders the config template, which pins the source there and records
whether the 1Password app is present, and applies. `apply` runs
[`home/.chezmoiscripts/`](home/.chezmoiscripts/): on a Mac, Homebrew when it is absent (the one
password prompt: its installer needs sudo) and then the Homebrew bundle of apps; on either OS,
mise (installing itself first) with every CLI and runtime; macOS defaults and the Caps Lock agent
when their inputs change; and provisioning every time (Claude Code CLI, gh extensions, the
plugins `settings.json` declares). The steps behind `gh auth login` converge on the second
apply. [`home/.chezmoiignore`](home/.chezmoiignore) names what is Mac-only. On Linux, zsh is not
the login shell until `chsh -s "$(command -v zsh)"`, once.

An ephemeral container (a Claude Code cloud environment's setup script) takes one line, which
leaves neither source nor binary behind; a devcontainer points VS Code's `dotfiles.repository`
at this repo, which runs [`install.sh`](install.sh) and keeps the checkout.

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --one-shot alxjrvs/dotFiles
```

Day to day: edit in the checkout, `chezmoi apply`, commit, PR. GitHub is the gate: the main
ruleset requires a pull request and the `lint` check, push protection stops a secret before it
lands, and [`.github/gate.sh`](.github/gate.sh) is those settings as a command. Drift:
`chezmoi verify`. Upgrades: `mise upgrade`, `chezmoi upgrade`, `brew upgrade --cask <app>`;
apply reconciles and never upgrades. After editing the config template: `chezmoi apply --init`.
Another machine: `chezmoi update`.

## The agent

The agent is you. `gh auth login` is the one GitHub credential and `gh` the one GitHub tool;
git borrows the token. Agent commits carry the `Claude` author and the co-author trailer on the
branch; the squash rewrites both, so on `main` the PR is the record.
Branch protection and the never-push-main rule are the gate.

A container has no token; its secrets are the environment's own. Project secrets are 1Password
Environments, mounted, never on disk. Employer config is the employer's marketplace, installed by
its own tooling; nothing here enables it.

## Layout

```
.chezmoiroot            "home": the source state lives one directory down
.github/gate.sh         the repo settings that are not files: ruleset, scanning, merge policy
install.sh              chezmoi's generated container hook: install chezmoi if missing, init --apply from here
home/                   what lands in ~  (dot_zshrc → ~/.zshrc, dot_config/… → ~/.config/…)
home/.chezmoiscripts/   machine setup: Homebrew and its apps (Mac), mise with every CLI (both), macOS defaults, Caps Lock, provision
home/dot_claude/        user-global Claude Code config
home/.chezmoi*          chezmoi's own contract: config template (source path, 1Password predicate), version floor, ignores, externals
docs/GOTCHAS.md         traps still armed and the rule each forces; never applied to a machine
```

## Forking

The repo settings that are not files, secret scanning, push protection and the default-branch
ruleset (pull request only, squash, the `lint` check, no bypass), are one idempotent command,
run once by the owner:

```bash
.github/gate.sh
```

`git grep -ilE 'alxjrvs|GitHubSSH'` finds every file to change: git identity and signing
key (`home/dot_config/git/config.tmpl`); the marketplace, plugin and co-author trailer
(`home/dot_claude/settings.json.tmpl`); the SSH items
(`home/dot_config/1Password/ssh/agent.toml`); the launchd label (the plist under `home/Library`
and its script); and the persona (`home/dot_claude/CLAUDE.md`).

MIT — see [`LICENSE`](LICENSE).
