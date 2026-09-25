# dotFiles

macOS dotfiles for [alxjrvs](https://github.com/alxjrvs), managed by
[chezmoi](https://www.chezmoi.io). `home/` is the source state. Principles:
[`CLAUDE.md`](CLAUDE.md#principles).

## Fresh Mac

Run this, then open a new terminal (the applied `~/.zprofile` puts `gh` and `chezmoi` on PATH):

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin init --apply alxjrvs/dotFiles
```

```bash
gh auth login --scopes workflow && chezmoi apply
```

The first apply asks for your password once, for Homebrew. Anything that needs `gh auth login`
lands on the second. The `workflow` scope lets a push change `.github/workflows/`.

Between the two commands:

- Sign in to 1Password. Under Settings › Developer, turn on Use the SSH Agent and Integrate with
  1Password CLI. Commits sign through the agent.
- Run `claude` once to log in.
- Log out and back in once, for the keyboard defaults.

To hack on this repo, clone it to `~/Code/dotFiles`; chezmoi keeps its own copy.

## Day to day

| | |
|---|---|
| change something | in a worktree: edit, `mise run lint`, `mise run apply-check`, commit, PR |
| a PR landed | `chezmoi update` |
| drift | `chezmoi verify` |
| upgrade | `mise self-update`, `mise upgrade`, `chezmoi upgrade`, `brew outdated --greedy` then `brew upgrade <name>` (apply never upgrades) |
| add a work org | one entry in `home/.chezmoidata.toml` |
| the repo settings | [`.github/gate.sh`](.github/gate.sh), run by the owner |

A Mac on power never idles to sleep, so an unattended `/loop` keeps running; closing the lid
still stops it. On the web, an expired claude.ai login stalls a loop until the next `/login`.
A push that changes `.github/workflows/` needs the `workflow` scope; its rejection reads like
branch protection.

GitHub is the gate: `main` takes only squash-merged pull requests with the `lint` check green,
and push protection stops a secret before it lands. Agents act as you: `gh auth login` is the one
credential and `gh` is the one tool.

## Layout

```
.chezmoiroot            "home": the source state lives one directory down
mise.toml               this repo's pinned linters and its two checks, lint and apply-check
.github/                CI, apply-check.sh, and gate.sh (the repo settings that are not files)
.claude/                this repo's Claude Code config: the loop and a web-session setup hook
home/                   what lands in ~  (dot_zshrc → ~/.zshrc, dot_config/… → ~/.config/…)
home/.chezmoiscripts/   machine setup: Homebrew, mise, Caps Lock, macOS defaults, sleep, provisioning, apps
home/.chezmoitemplates/ the declared keys of ~/.claude/settings.json
home/dot_claude/        user-global Claude Code config, and the loop a bare `/loop` runs
home/.chezmoi*          chezmoi's own files: config template, data (work orgs), version floor, externals
```

## Forking

`git grep -ilE 'alxjrvs|GitHubSSH|thegnar'` lists every file to change. Then run
`.github/gate.sh`.

MIT — see [`LICENSE`](LICENSE).
