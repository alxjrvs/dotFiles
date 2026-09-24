# dotFiles

macOS and Linux dotfiles for [alxjrvs](https://github.com/alxjrvs), managed by
[chezmoi](https://www.chezmoi.io). `home/` is the source state. Principles:
[`CLAUDE.md`](CLAUDE.md#principles).

## Fresh machine

Run this, then open a new terminal (the applied `~/.zprofile` puts `gh` and `chezmoi` on PATH):

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin init --apply alxjrvs/dotFiles
```

```bash
gh auth login --scopes workflow && chezmoi apply
```

On a Mac the first apply asks for your password once, for Homebrew. Anything that needs
`gh auth login` lands on the second apply. The `workflow` scope lets a push change
`.github/workflows/`; the login flow never asks for it. A machine that is already logged in adds
it with `gh auth refresh -h github.com -s workflow`.

On a Mac, between the two commands:

- Sign in to 1Password. Under Settings › Developer, turn on Use the SSH Agent, Integrate with
  1Password CLI, and Integrate with MCP clients. The first commit signs through the agent.
- Run `claude` once to log in.
- Log out and back in once, for the keyboard defaults.

To keep hacking on this repo, clone it to `~/Code/dotFiles`. chezmoi keeps its own copy.

A Codespace or devcontainer runs [`install.sh`](install.sh), which applies from wherever it was
cloned; re-run it to re-apply. Pointing VS Code's `dotfiles.repository` at this repo is a
by-hand step.

## Day to day

| | |
|---|---|
| change something | in a worktree: edit, `mise run lint`, `mise run apply-check`, commit, PR |
| a PR landed | `chezmoi update` |
| drift | `chezmoi verify` |
| upgrade | `mise upgrade`, `chezmoi upgrade`, `brew outdated --cask --greedy` then `brew upgrade --cask <app>` (apply never upgrades) |
| the config template changed | `chezmoi init` |
| add a work org | one entry in `home/.chezmoidata.toml` |
| the repo settings | [`.github/gate.sh`](.github/gate.sh), run by the owner, here and in [`alxjrvs/oberon`](https://github.com/alxjrvs/oberon) |

A Mac on power does not idle to sleep, so an unattended `/loop` keeps running; closing the lid
still stops it. On the web, an expired claude.ai login stalls a loop until the next `/login`.

GitHub is the gate. `main` takes only squash-merged pull requests with the `lint` check green,
and push protection stops a secret before it lands. Agents act as you: `gh auth login` is the
one credential and `gh` is the one tool.

## Layout

```
.chezmoiroot            "home": the source state lives one directory down
mise.toml               this repo's pinned linters and its two checks, lint and apply-check
.github/                CI, apply-check.sh, and gate.sh (the repo settings that are not files)
.claude/                this repo's Claude Code config: the loop and a web-session setup hook
install.sh              chezmoi's generated devcontainer hook
home/                   what lands in ~  (dot_zshrc → ~/.zshrc, dot_config/… → ~/.config/…)
home/.chezmoiscripts/   machine setup: Homebrew, mise, macOS defaults, sleep, provisioning, apps, Caps Lock
home/.chezmoitemplates/ the declared keys of ~/.claude/settings.json
home/dot_claude/        user-global Claude Code config, and the loop a bare `/loop` runs
home/.chezmoi*          chezmoi's own files: config template, data (work orgs), version floor, ignores, externals
docs/GOTCHAS.md         traps still armed and the rule each forces
```

## Forking

`git grep -ilE 'alxjrvs|GitHubSSH|thegnar'` finds every file to change: git identity, work
orgs and signing key, the marketplace and plugin, the SSH item, the launchd label, and the
persona. Then run `.github/gate.sh`.

MIT — see [`LICENSE`](LICENSE).
