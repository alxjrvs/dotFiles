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
Claude Code CLI, `mise install`, gh extensions). Then `gh auth login` and a second
`chezmoi apply` for the gh extensions.

Day to day: edit in the checkout (`chezmoi cd`), `chezmoi apply`, commit, PR. On another Mac,
`chezmoi update` pulls and applies what landed. Once per clone: `lefthook install`.

## The agent, once per machine

Four commands from a normal terminal, where `op` can reach 1Password (it cannot from inside
Claude Code's Bash sandbox). Repeat the second when the agent's PAT is rotated, at most yearly.

1. The service-account token, into the login keychain. `-w` last: it prompts, so the token never
   lands on argv or in shell history.

   ```bash
   security add-generic-password -a "$USER" -s op-claude-agent -w
   ```

2. The agent's GitHub PAT, into the login keychain for git. The helper writes the item, so the
   helper is on its ACL; `reject` first because an older Apple git's `approve` is a silent no-op
   on an existing item.

   ```bash
   cred() { printf 'protocol=https\nhost=github.com\nusername=claude-agent\n'; [ "$1" = approve ] && { printf 'password='; op read op://claude-agent/claude-git-pat/credential; }; echo; }
   cred reject | git -c credential.helper=osxkeychain credential reject
   cred approve | git -c credential.helper=osxkeychain credential approve
   ```

3. The two user-scoped MCP servers. They live only in `~/.claude.json`, which nothing tracks.
   The GitHub one is the hosted server with the agent's PAT as a bearer header; if it refuses a
   fine-grained PAT, `brew install github-mcp-server` and register the stdio form instead.

   ```bash
   claude mcp add --scope user 1password -- /Applications/1Password.app/Contents/MacOS/1password-mcp
   helper='~/.local/bin/op-sa read op://claude-agent/claude-git-pat/credential | jq -Rc "{Authorization: (\"Bearer \" + .)}"'
   claude mcp add-json --scope user github "$(jq -cn --arg h "$helper" '{type:"http",url:"https://api.githubcopilot.com/mcp/",headersHelper:$h}')"
   ```

Preview without touching anything: `chezmoi apply --dry-run --verbose`. Drift:
`chezmoi verify --exclude scripts` and `brew bundle check --no-upgrade --file=~/.config/homebrew/Brewfile`, by hand.

Upgrades: `brew upgrade --formula` and `mise upgrade`; Dependabot opens a monthly PR for the
workflow's actions; the statusline tag in `home/.chezmoiexternal.toml` moves by hand.

## Layout

```
.chezmoiroot            "home" — the source state lives one directory down
home/                   what lands in ~  (dot_zshrc → ~/.zshrc, dot_config/… → ~/.config/…)
home/run_*              machine setup: brew (onchange), macOS defaults (onchange), provision (every apply)
home/dot_claude/        user-global Claude config: CLAUDE.md, settings.json, rules
home/.chezmoi*          chezmoi's own contract: ignore, externals
docs/GOTCHAS.md         traps still armed and the rule each forces; never applied to a machine
```

## Forking this repo

`git grep -ilE 'alxjrvs|claude-agent|GitHubSSH'` finds every file. In order of what breaks first: git identity and
signing key (`home/dot_gitconfig`, `home/private_dot_ssh/allowed_signers`), the agent identity
(`home/dot_claude/settings.json`), the `op://claude-agent/…` references (`settings.json` and
this README), and the SSH items in
`home/dot_config/1Password/ssh/agent.toml`.

What an agent may write is scoped by ACTION, not by repo owner, so there is no list of repos to
port — the `gh` verb rules in `permissions.deny` are the whole of it.

## Where the reasoning lives

Beside the thing it explains: a run script's rationale is in its comment block. Traps that no file asserts on its own are in [`docs/GOTCHAS.md`](docs/GOTCHAS.md);
history is in the PRs.

MIT — see [`LICENSE`](LICENSE).
