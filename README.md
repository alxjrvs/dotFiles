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

That clones to `~/.local/share/chezmoi` and applies: files into `~`, then the three `run_`
scripts in [`home/`](home/): the Homebrew bundle (when the Brewfile changes), macOS defaults
(when they change), and provisioning on every apply (Claude Code CLI, `mise install`, gh
extensions). Then `gh auth login`, `chezmoi apply` again for the extensions, and
`lefthook install` in the checkout.

Day to day: edit in the checkout (`chezmoi cd`), `chezmoi apply`, commit, PR. Another Mac:
`chezmoi update`. Drift: `chezmoi verify --exclude scripts` and `brew bundle check`. Upgrades:
`brew upgrade --formula`, `mise upgrade`; the statusline tag in `home/.chezmoiexternal.toml`
moves by hand.

## The agent, once per machine

From a normal terminal, where `op` can reach 1Password (it cannot inside Claude Code's Bash
sandbox). Step 2 again when the PAT is rotated, at most yearly.

1. The 1Password service-account token (`read_items` on the `claude-agent` vault) into the
   login keychain. `-w` last: it prompts, so the token never lands on argv or in history.

   ```bash
   security add-generic-password -a "$USER" -s op-claude-agent -w
   ```

2. The agent's GitHub PAT into the login keychain for git. git's helper writes the item, which
   puts the helper on its ACL; `reject` first because an older Apple git's `approve` is a
   silent no-op on an existing item.

   ```bash
   cred() { printf 'protocol=https\nhost=github.com\nusername=claude-agent\n'; [ "$1" = approve ] && { printf 'password='; op read op://claude-agent/claude-git-pat/credential; }; echo; }
   cred reject | git -c credential.helper=osxkeychain credential reject
   cred approve | git -c credential.helper=osxkeychain credential approve
   ```

3. The two user-scoped MCP servers, which live only in `~/.claude.json`. GitHub is the hosted
   server with the PAT as a bearer header; if it refuses a fine-grained PAT,
   `brew install github-mcp-server` and register the stdio form instead.

   ```bash
   claude mcp add --scope user 1password -- /Applications/1Password.app/Contents/MacOS/1password-mcp
   helper='~/.local/bin/op-sa read op://claude-agent/claude-git-pat/credential | jq -Rc "{Authorization: (\"Bearer \" + .)}"'
   claude mcp add-json --scope user github "$(jq -cn --arg h "$helper" '{type:"http",url:"https://api.githubcopilot.com/mcp/",headersHelper:$h}')"
   ```

## Layout

```
.chezmoiroot            "home": the source state lives one directory down
home/                   what lands in ~  (dot_zshrc → ~/.zshrc, dot_config/… → ~/.config/…)
home/run_*              machine setup: brew (onchange), macOS defaults (onchange), provision (every apply)
home/dot_claude/        user-global Claude Code config
docs/GOTCHAS.md         traps still armed and the rule each forces; never applied to a machine
```

## Forking

`git grep -ilE 'alxjrvs|claude-agent|GitHubSSH'` finds every file: git identity and signing key
(`home/dot_gitconfig`, `home/private_dot_ssh/allowed_signers`), the agent identity
(`home/dot_claude/settings.json`), the `op://claude-agent/…` references (`settings.json`, this
README), and the SSH items in `home/dot_config/1Password/ssh/agent.toml`.

MIT — see [`LICENSE`](LICENSE).
