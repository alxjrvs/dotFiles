# dotFiles

macOS and Linux dotfiles for [alxjrvs](https://github.com/alxjrvs), managed by
[chezmoi](https://www.chezmoi.io). `home/` is the source state. Principles:
[`CLAUDE.md`](CLAUDE.md#principles).

## Fresh machine

A Mac, in two lines, the second of which is a login:

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply --source ~/Code/dotFiles alxjrvs/dotFiles
gh auth login && chezmoi apply
```

`init` clones into `~/Code/dotFiles`, renders the config template, which pins the source there,
and applies. `apply` runs [`home/.chezmoiscripts/`](home/.chezmoiscripts/): Homebrew when it is
absent (the one password prompt: its installer needs sudo), provisioning every time (Claude Code
CLI, mise, gh extensions, plugins, MCP servers), then the files, then the Homebrew bundle and
macOS defaults when they change. The steps behind `gh auth login` converge on the second apply.
[`home/.chezmoiignore`](home/.chezmoiignore) names what is Mac-only.

A container gets the portable core (shell, git, editor, `~/.claude`) and nothing Mac-only. A
Claude Code cloud environment's setup script is one line; a devcontainer points VS Code's
`dotfiles.repository` at this repo, which runs [`install.sh`](install.sh).

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --one-shot alxjrvs/dotFiles
```

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
the `claude-agent` vault, minted with `--expires-in` so its expiry is a date and not an
incident. Once per Mac, put its token in the login keychain where `op-sa` reads it (`-w` last:
it prompts, so the token never lands on argv or in history). A container has no token; its
secrets are the environment's own. Project secrets are 1Password Environments, mounted, never
on disk.

```bash
security add-generic-password -a "$USER" -s op-claude-agent -w
```

## Layout

```
.chezmoiroot            "home": the source state lives one directory down
install.sh              chezmoi's generated container hook: install chezmoi if missing, init --apply from here
home/                   what lands in ~  (dot_zshrc → ~/.zshrc, dot_config/… → ~/.config/…)
home/.chezmoiscripts/   machine setup: Homebrew (when absent), provision (every apply, before files), brew and macOS defaults (onchange)
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
