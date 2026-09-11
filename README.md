# dotFiles

macOS and Linux dotfiles for [alxjrvs](https://github.com/alxjrvs), managed by
[chezmoi](https://www.chezmoi.io). `home/` is the source state. Principles:
[`CLAUDE.md`](CLAUDE.md#principles).

## Fresh machine

A Mac:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install chezmoi
git clone https://github.com/alxjrvs/dotFiles ~/Code/dotFiles
chezmoi init --source ~/Code/dotFiles --apply
gh auth login && chezmoi apply
```

A Linux box gets the portable core (shell, git, editor, `~/.claude`) and nothing Mac-only;
packages are its own business:

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin
git clone https://github.com/alxjrvs/dotFiles ~/Code/dotFiles
chezmoi init --source ~/Code/dotFiles --apply
gh auth login
```

`init` renders the config template, which pins the source to that checkout. `apply` runs
[`home/.chezmoiscripts/`](home/.chezmoiscripts/): provisioning first, every time (Claude Code
CLI, mise, gh extensions, plugins, MCP servers), then the files, then the Homebrew bundle and
macOS defaults when they change. [`home/.chezmoiignore`](home/.chezmoiignore) names what is
Mac-only.

Day to day: edit in the checkout, `chezmoi apply`, commit, PR. GitHub is the gate: the main
ruleset requires a pull request and the `lint` check, and push protection stops a secret before
it lands. Drift: `chezmoi verify`.
Upgrades: `brew upgrade --formula`, `mise upgrade`; apply reconciles and never upgrades. Another
machine: `chezmoi update`.

## The agent

The agent is you. `gh auth login` is the one GitHub credential; git and the GitHub MCP borrow
it. Agent commits carry the `Claude` author and the co-author trailer. Branch protection and the
never-push-main rule are the gate.

Plugin tokens that are not GitHub's come from a 1Password service account with `read_items` on
the `claude-agent` vault. Once per machine, put its token where `op-sa` reads it: the login
keychain on a Mac (`-w` last: it prompts, so the token never lands on argv or in history), or
`~/.config/op-sa/token`, mode 0600, on Linux.

```bash
security add-generic-password -a "$USER" -s op-claude-agent -w
```

## Layout

```
.chezmoiroot            "home": the source state lives one directory down
home/                   what lands in ~  (dot_zshrc → ~/.zshrc, dot_config/… → ~/.config/…)
home/.chezmoiscripts/   machine setup: provision (every apply, before files), brew and macOS defaults (onchange)
home/dot_claude/        user-global Claude Code config
home/.chezmoi*          chezmoi's own contract: config template, version floor, ignores, externals, removals
docs/GOTCHAS.md         traps still armed and the rule each forces; never applied to a machine
```

## Forking

Three repo settings are not in the tree: secret scanning and push protection (Settings →
Code security), and a ruleset on the default branch that requires a pull request and the `lint`
status check.

`git grep -ilE 'alxjrvs|claude-agent|GitHubSSH'` finds every file: git identity and signing key
(`home/dot_config/git/config.tmpl`, `home/private_dot_ssh/allowed_signers`), the agent's author
(`home/dot_claude/settings.json`), the vault and keychain item (`settings.json`,
`home/dot_local/bin/executable_op-sa`), and the SSH items in
`home/dot_config/1Password/ssh/agent.toml`.

MIT — see [`LICENSE`](LICENSE).
