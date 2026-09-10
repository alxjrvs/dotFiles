# dotFiles

macOS dotfiles for [alxjrvs](https://github.com/alxjrvs), managed by
[chezmoi](https://www.chezmoi.io). `home/` is the source state. Principles:
[`CLAUDE.md`](CLAUDE.md#principles).

## Fresh machine

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install chezmoi
git clone https://github.com/alxjrvs/dotFiles ~/Code/dotFiles
chezmoi init --source ~/Code/dotFiles --apply
```

`init` renders `home/.chezmoi.toml.tmpl` into `~/.config/chezmoi/chezmoi.toml`, which pins the
source to that checkout; `apply` puts files into `~`, then runs the three `run_` scripts in
[`home/`](home/): the Homebrew bundle (when the Brewfile changes), macOS defaults (when they
change), and provisioning on every apply (Claude Code CLI, `mise install`, gh extensions, this
repo's commit hook, the MCP registrations, the agent's PAT). Then `gh auth login` and
`chezmoi apply` again for the extensions.

Day to day: edit in the checkout (`chezmoi cd`), `chezmoi apply`, commit, PR. Another Mac:
`chezmoi update`. Drift: `chezmoi verify` and `brew bundle check --global --no-upgrade`.
Upgrades: `brew upgrade --formula`, `mise upgrade`; the statusline tag in
`home/.chezmoiexternal.toml` moves by hand. After editing the config template, `chezmoi init`
again.

## The agent

**One agent step is by hand, once per machine**, and the rest of what the agent needs follows
from it on every apply. Mint a 1Password service account with `read_items` on the
`claude-agent` vault and store its token in the login keychain. `-w` last: it prompts, so the
token never lands on argv or in shell history.

```bash
security add-generic-password -a "$USER" -s op-claude-agent -w
```

From there `chezmoi apply` copies the agent's GitHub PAT out of the vault into the keychain
through git's own credential helper, and registers the 1Password and GitHub MCP servers. Rotate
the PAT in 1Password and the next apply propagates it. This runs at apply time because apply runs
outside Claude Code's Bash sandbox, and `op` cannot reach 1Password from inside it.

## Layout

```
.chezmoiroot            "home": the source state lives one directory down
home/                   what lands in ~  (dot_zshrc → ~/.zshrc, dot_config/… → ~/.config/…)
home/run_*              machine setup: brew (onchange), macOS defaults (onchange), provision (every apply)
home/dot_claude/        user-global Claude Code config
home/.chezmoi*          chezmoi's own contract: config template, version floor, externals, removals
docs/GOTCHAS.md         traps still armed and the rule each forces; never applied to a machine
```

## Forking

`git grep -ilE 'alxjrvs|claude-agent|GitHubSSH'` finds every file. What breaks first: git
identity and signing key (`home/dot_gitconfig`, `home/private_dot_ssh/allowed_signers`), the
agent's git identity (`home/dot_claude/settings.json`, `home/dot_config/git/agent.gitconfig`),
the vault references and keychain item names (`settings.json`, `home/run_after_50-provision.sh`,
`home/dot_local/bin/executable_op-sa`), and the SSH items in
`home/dot_config/1Password/ssh/agent.toml`.

MIT — see [`LICENSE`](LICENSE).
