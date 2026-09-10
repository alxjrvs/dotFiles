# dotFiles

macOS dotfiles for [alxjrvs](https://github.com/alxjrvs), managed by
[chezmoi](https://www.chezmoi.io). `home/` is the source state. Principles:
[`CLAUDE.md`](CLAUDE.md#principles).

## Fresh machine

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install chezmoi
chezmoi init --apply alxjrvs/dotFiles
```

`init --apply` clones this repo to `~/.local/share/chezmoi` and applies: files into `~`, then
the three `run_` scripts in [`home/`](home/): the Homebrew bundle (re-run when the Brewfile
changes), macOS defaults (re-run when they change), and an every-apply provision script (the
Claude Code CLI, `mise install`, gh extensions, the MCP registrations, the agent's PAT). Then
`gh auth login` and a second `chezmoi apply` for the gh extensions.

Day to day: edit in the checkout (`chezmoi cd`), `chezmoi apply`, commit, PR. Another Mac:
`chezmoi update`. Drift: `chezmoi verify --exclude scripts` and `brew bundle check`. Upgrades:
`brew upgrade --formula`, `mise upgrade`; the statusline tag in `home/.chezmoiexternal.toml`
moves by hand.

## The agent

**One agent step is by hand, once per machine**, and the rest of what the agent needs follows
from it on every apply. Mint a 1Password service account with `read_items` on the
`claude-agent` vault and store its token in the login keychain. `-w` last: it prompts, so the
token never lands on argv or in shell history.

From a normal terminal, where `op` can reach 1Password (it cannot inside Claude Code's Bash
sandbox). Step 2 again when the PAT is rotated, at most yearly.

From there `chezmoi apply` copies the agent's GitHub PAT out of the vault into the keychain
through git's own credential helper, and registers the 1Password and GitHub MCP servers. Rotate
the PAT in 1Password and the next apply propagates it. This runs at apply time because apply runs
outside Claude Code's Bash sandbox, which is the only place `op` can reach 1Password at all.

Preview without touching anything: `chezmoi apply --dry-run --verbose`. Drift:
`chezmoi verify --exclude scripts` and `brew bundle check --global --no-upgrade`, by hand.

Upgrades: `brew upgrade --formula` and `mise upgrade`; Dependabot opens a monthly PR for the
workflow's actions; the statusline tag in `home/.chezmoiexternal.toml` moves by hand.

## Layout

```
.chezmoiroot            "home": the source state lives one directory down
home/                   what lands in ~  (dot_zshrc → ~/.zshrc, dot_config/… → ~/.config/…)
home/run_*              machine setup: brew (onchange), macOS defaults (onchange), provision (every apply)
home/dot_claude/        user-global Claude config: CLAUDE.md, settings.json
home/.chezmoi*          chezmoi's own contract: ignore, externals
docs/GOTCHAS.md         traps still armed and the rule each forces; never applied to a machine
```

## Forking

`git grep -ilE 'alxjrvs|claude-agent|GitHubSSH'` finds every file: git identity and signing key
(`home/dot_gitconfig`, `home/private_dot_ssh/allowed_signers`), the agent identity
(`home/dot_claude/settings.json`), the `op://claude-agent/…` references (`settings.json`, this
README), and the SSH items in `home/dot_config/1Password/ssh/agent.toml`.

MIT — see [`LICENSE`](LICENSE).
