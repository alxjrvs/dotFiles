# dotFiles

macOS and Linux dotfiles for [alxjrvs](https://github.com/alxjrvs), managed by
[chezmoi](https://www.chezmoi.io). `home/` is the source state. Principles:
[`CLAUDE.md`](CLAUDE.md#principles).

## Fresh machine

One line, then a login in a new terminal (the applied `~/.zprofile` is what puts `gh` and
`chezmoi` on PATH):

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin init --apply --source ~/Code/dotFiles alxjrvs/dotFiles
```

```bash
gh auth login --scopes workflow && chezmoi apply
```

The first apply asks for a password once (Homebrew's installer, on a Mac); what waits on
`gh auth login` converges on the second. `workflow` is the scope a push touching
`.github/workflows/` needs and the login flow never asks for; a machine already logged in gets it
with `gh auth refresh -h github.com -s workflow`. On a Mac, between the two: sign in to 1Password
and turn on Settings › Developer › Use the SSH Agent, Integrate with 1Password CLI and Integrate
with MCP clients (the first commit signs through the agent); run `claude` once to log in; log
out once for the keyboard defaults. A Codespace or a remote devcontainer runs
[`install.sh`](install.sh); pointing VS Code's `dotfiles.repository` at this repo is by hand, and
nothing here sets it.

## Day to day

| | |
|---|---|
| change something | in a worktree: edit, `chezmoi apply --source "$PWD"` from its root, commit, PR |
| a PR landed, here or elsewhere | `chezmoi update` |
| drift | `chezmoi verify` |
| upgrade | `mise upgrade`, `chezmoi upgrade`, `brew outdated --cask --greedy` then `brew upgrade --cask <app>` (most casks self-update, so a bare `outdated` is silent); apply never upgrades |
| the config template changed | `chezmoi apply --init`, from `~/Code/dotFiles` and never a worktree |
| the repo settings | [`.github/gate.sh`](.github/gate.sh), once per repo, by the owner: here and [`alxjrvs/oberon`](https://github.com/alxjrvs/oberon), which every fresh bootstrap installs from |

An unattended run happens on both surfaces and each stops its own way: on the Mac, idle sleep
or a closed lid ends a `/loop` mid-flight and leaves a pushed branch with no merge; on the web,
an expired claude.ai login stalls it until the next `/login`.

GitHub is the gate: `main` takes squash-merged pull requests with the `lint` check green, and
push protection stops a secret before it lands. The agent is you: `gh auth login` is the one
credential, `gh` the one tool, git borrows the token, and the squash-merged PR is the record.

## Layout

```
.chezmoiroot            "home": the source state lives one directory down
.github/gate.sh         the repo settings that are not files: ruleset, scanning, merge policy
install.sh              chezmoi's generated devcontainer hook
home/                   what lands in ~  (dot_zshrc → ~/.zshrc, dot_config/… → ~/.config/…)
home/.chezmoiscripts/   machine setup: Homebrew (Mac), mise with every CLI (both), macOS defaults, provisioning, the Mac's apps, Caps Lock
home/dot_claude/        user-global Claude Code config, and the standing loop a bare `/loop` runs
home/.chezmoi*          chezmoi's own contract: config template, version floor (the oldest chezmoi that reads archive-file externals), ignores, externals
docs/GOTCHAS.md         traps still armed and the rule each forces
```

## Forking

`git grep -ilE 'alxjrvs|GitHubSSH'` finds every file to change: git identity and signing key,
the marketplace and plugin, the SSH item, the launchd label, and the persona. Then
`.github/gate.sh`.

MIT — see [`LICENSE`](LICENSE).
