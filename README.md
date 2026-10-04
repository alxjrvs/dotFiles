# dotFiles

macOS dotfiles for [alxjrvs](https://github.com/alxjrvs), managed by
[chezmoi](https://www.chezmoi.io). `home/` is the source state. Principles:
[`CLAUDE.md`](CLAUDE.md#principles).

## Fresh Mac

Run this, then open a new terminal (the applied `~/.zprofile` puts `gh` and `chezmoi` on PATH):

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin init --apply --use-builtin-git=true alxjrvs/dotFiles
```

```bash
gh auth login --scopes workflow && chezmoi apply
```

The first apply asks for your password once, for Homebrew, and whether this is your personal Mac:
a work Mac keeps the apps its employer installs, because Homebrew cleanup never runs there. Anything
that needs `gh auth login` lands on the second. The `workflow` scope lets a push change
`.github/workflows/`.

Between the two commands:

- Sign in to 1Password. Under Settings › Developer, turn on Use the SSH Agent and Integrate with
  1Password CLI. Commits sign through the agent. Registering its key on GitHub needs
  `admin:ssh_signing_key`, a scope that could mint Verified commits as you: grant it for that one
  `gh ssh-key add --type signing` (`gh auth refresh -s admin:ssh_signing_key`), then drop it
  (`gh auth refresh -r admin:ssh_signing_key`).
- Run `claude` once to log in.
- Log out and back in once, for the keyboard defaults.

To hack on this repo, clone it to `~/Code/dotFiles`; chezmoi keeps its own copy.

## Day to day

| | |
|---|---|
| change something | in a worktree: edit, `mise run lint`, `mise run apply-check`, commit, PR; an agent's `claude/` PR merges itself on green unless it touches the floor |
| a PR landed | `chezmoi update` |
| drift | `chezmoi verify` |
| upgrade | nightly: `mise run upkeep` upgrades, converges a green main and checks every gated repo against gate.sh; a failure opens an issue here that pings your phone. Apps update themselves (gcloud: `gcloud components update`) |
| a pin | monthly: a Routine runs `/bump` ([`.claude/skills/bump`](.claude/skills/bump/SKILL.md)) |
| add a work org | one entry in `home/.chezmoidata.toml` |
| the repo settings | [`.github/gate.sh`](.github/gate.sh), run by the owner; upkeep names any drift, and `gate.sh --apply <owner>` converges every repo it safely can |

The Claude app keeps the Mac awake while a session works; closing the lid still sleeps it. On the
web, an expired claude.ai login stalls a session until the next `/login`.
A push that changes `.github/workflows/` needs the `workflow` scope; its rejection reads like
branch protection.

GitHub is the gate: `main` takes only squash-merged pull requests with the `lint` check green,
and push protection stops a secret before it lands. Agents act as you, through `gh` or any connector
available.

## Layout

```
.chezmoiroot            "home": the source state lives one directory down
mise.toml               this repo's pinned linters and its two checks, lint and apply-check
.github/                CI, apply-check.sh, gate.sh (the repo settings that are not files), main-green.sh
.claude/                this repo's Claude Code config: the verify and bump skills, and a web-session setup hook
home/                   what lands in ~  (dot_zshrc → ~/.zshrc, dot_config/… → ~/.config/…)
home/.chezmoiscripts/   machine setup: Homebrew, mise, launchd agents, macOS defaults, provisioning, apps, and one
                        Claude desktop app per extra account
home/.chezmoitemplates/ the declared keys of ~/.claude/settings.json
home/dot_claude/        user-global Claude Code config, skills, and the `audit` workflow
home/.chezmoi*          chezmoi's own files: config template, data (who and which orgs), version floor, ignore and remove lists
```

## Forking

Fork it, turn on its Actions (GitHub leaves a fork's workflows off), and edit
`home/.chezmoidata.toml`: who you are lives there alone. Then run `.github/gate.sh` from your
clone, and the Fresh Mac command with your fork's name. The monthly bump is a Routine on your own
account: `/schedule` one whose prompt is `/bump`. Keep LICENSE's copyright line;
MIT requires it.

MIT — see [`LICENSE`](LICENSE).
