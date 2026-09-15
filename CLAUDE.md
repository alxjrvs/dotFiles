# dotFiles

A [chezmoi](https://www.chezmoi.io) source repo; there is no engine code. `home/` is the source
state (chezmoi's `dot_`/`private_` naming), everything else is repo plumbing. `chezmoi apply`
reconciles the machine; `chezmoi verify` is the drift signal.

## Principles

North Star: **small, exemplary, easily shareable: a senior engineer's showpiece, not an
over-engineered personal artifact.** When a rule and a principle collide, surface the tradeoff.

- Native over special: deleting custom code for a built-in is the highest-value change.
- Guilty until proven load-bearing: every dependency, wrapper, and line earns its weight.
- One source, two hosts: a Mac has everything; Linux is a container with no 1Password app, no
  signing and no sudo. `.chezmoiignore` names what is Mac-only, and templates branch on
  `.chezmoi.os` alone. No by-hand step remains that `chezmoi apply` could converge, except the
  removals and the external bumps, which cost more to converge than to do.
- Standard, and agentic-enabled: 1Password, git, ssh, `gh`, MCP stay stock, wired for agents.
- Keep it legible: one line on the decision, nothing on the mechanism.

## Local facts

- `home/dot_claude/` is the **user-global** Claude config (`~/.claude/`). The repo-root
  `.claude/` is this repo's project scope. Don't conflate them.
- `~/Code/dotFiles` is chezmoi's source on a machine bootstrapped by hand and stays on `main`;
  only `chezmoi update` moves it. In a container the source is wherever `install.sh` was cloned,
  so an agent asks `chezmoi source-path`. A change is made in a worktree and applied from there
  with `--source "$PWD"`.
- Every CLI and runtime is a mise tool, on both OSes, bar the `1password-cli` and `gcloud-cli`
  casks (the latter's `python@3.14` dependency puts a second `python3` on a Mac's PATH) and
  `postgresql@17`, a launchd service brew runs and mise would only put on PATH; a Mac's apps are
  Brewfile casks; chezmoi, mise and the Claude Code CLI are their own installers' (`~/.local/bin`)
  and git is the system's. `chezmoi apply` reconciles and never upgrades, and what the Brewfile
  does not name it uninstalls, so a Homebrew formula shadowing a mise tool cannot accumulate.
- `~/Code/.metadata_never_index` is a chezmoi target, so Spotlight indexes no repo on this
  machine. It is one empty file and it earns its place: 58G and forty-odd `node_modules`
  under `~/Code`, plus every agent worktree, kept `mds_stores` from ever settling. Code is
  searched with `rg` and `fd`, which read the disk and not the index.
- A worktree is the unit of work, either kind: Claude Code cuts its own under
  `.claude/worktrees/`, `git worktree add` is the by-hand one, and both apply from the worktree
  root with `--source "$PWD"`. Never `--init` from either.
- Machine setup is `home/.chezmoiscripts/`, flat: guarded every-apply scripts for Homebrew and
  provisioning, `onchange` on the Brewfile, mise config and Caps Lock plist hashes and on the macOS
  defaults. mise installs itself.
- The macOS defaults are applied, not converged: `verify` runs no script and never sees them.
- One GitHub identity: `gh auth login`; the login keychain on a Mac, a plaintext
  `~/.config/gh/hosts.yml` in a container, where the container is the boundary around a token
  scoped `repo`, `read:org`, `gist` and `workflow` across his account and the five organizations
  he administers (gh warns, cli/cli#10108). Never `--insecure-storage` on a Mac.
- `home/dot_claude/loop.md` is what a bare `/loop` runs in any repo without its own
  `.claude/loop.md`; `/loop <prompt>` ignores it.
- nvim is `$EDITOR` and nothing more: no plugins, no language servers.
- The terminal owns the palette: a tool names a theme or an ANSI color, never a hex code.
- `home/dot_claude/private_settings.json.tmpl` carries divergences from defaults plus every key
  the app writes on its own, in the order the CLI's writer emits (which is not the docs' order:
  `sandbox` is enabled, network, filesystem, credentials) so its rewrites are not drift; don't
  tidy a key away without reading why it is there.
- Employer config is the employer's marketplace, installed by its tooling; nothing here enables it.
- Secrets: `op://` references only, never a plaintext token, and nothing here prints one.
- A source file's mode comes from its name (`executable_`, `private_`), never from the checkout.
- CI's `lint` job is the one required check, a summary over static checks on ubuntu and an
  apply on macOS and on ubuntu; every check lives behind it. The repo settings that are not files are
  `.github/gate.sh`.
- Traps still armed and the rule each forces: `docs/GOTCHAS.md`. History is the PRs.
