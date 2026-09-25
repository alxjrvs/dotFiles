# dotFiles

A [chezmoi](https://www.chezmoi.io) source repo; there is no engine code. `home/` is the source
state (chezmoi's `dot_`/`private_` naming); everything else is repo plumbing. `chezmoi apply`
reconciles the machine, and `chezmoi verify` reports drift.

## Principles

North Star: **small, exemplary, easily shareable: a senior engineer's showpiece, not an
over-engineered personal artifact.** When a rule and a principle collide, surface the tradeoff.

- Native over special: deleting custom code for a built-in is the highest-value change.
- Guilty until proven load-bearing: every dependency, wrapper, and line earns its weight.
- One host, the Mac. A Claude Code web session is Linux and gets this repo, never `~`: the checks
  run there and nothing applies. No by-hand step remains that `chezmoi apply` could converge,
  except external bumps.
- Standard, and agentic-enabled: 1Password, git, ssh, `gh`, MCP stay stock, wired for agents.
- Keep it legible: one line on the decision, nothing on the mechanism.

## How a change lands

1. Work in a worktree of a clone (`~/Code/dotFiles` on the Mac).
2. Prove it with `mise run lint` and `mise run apply-check`. The second applies the source into a
   temporary home, so it is safe anywhere.
3. Open a PR. `lint` is the one required check; CI runs the same two tasks on a Mac.
4. After it merges, `chezmoi update` applies it. chezmoi's own source is
   `~/.local/share/chezmoi`, and nothing else moves it.

Never apply a worktree to the real home directory. A PR that touches `home/dot_claude/` or
`home/.chezmoiscripts/` changes what agents may do or what runs on the next apply, so a person
merges it; an agent leaves it open at green.

## Local facts

- `home/dot_claude/` is the **user-global** Claude config (`~/.claude/`). The repo-root
  `.claude/` is this repo's project scope. Don't conflate them.
- `~/.claude/settings.json` is a modify template: chezmoi enforces the keys declared in
  `home/.chezmoitemplates/claude-settings.json` and leaves every other key to the app.
- Every CLI and runtime is a mise tool (`home/dot_config/mise/config.toml`). The exceptions are
  the `1password-cli`, `gcloud-cli` and `ngrok` casks, and `postgresql@17`, a service brew runs.
  The apps are Brewfile casks. chezmoi, mise and the Claude Code CLI come from their
  own installers into `~/.local/bin`; git is the system's.
- This repo's own linters are pinned in the root `mise.toml`, not installed machine-wide.
- `chezmoi apply` never upgrades anything. When the Brewfile changes, it also uninstalls every
  Homebrew package the Brewfile does not name.
- Machine setup is `home/.chezmoiscripts/`. Homebrew, sleep and provisioning run on
  every apply behind a guard. mise, the Caps Lock plist and the Brewfile re-run when their file
  changes (the Brewfile last), and the macOS defaults re-run when the script itself changes.
- The macOS defaults are applied, not converged: `verify` runs no script and never sees them.
- `~/Code/.metadata_never_index` keeps Spotlight out of every repo; its indexer never settled
  under `~/Code`. Search code with `rg` and `fd`.
- One GitHub login: `gh auth login`, stored in the login keychain. Never `--insecure-storage`.
- Commits use `alxjrvs@gmail.com`, except in the work orgs listed in `home/.chezmoidata.toml`,
  which use the work email.
- `home/dot_claude/loop.md` is what a bare `/loop` runs in any repo without its own
  `.claude/loop.md`; `/loop <prompt>` ignores it.
- nvim is `$EDITOR` and nothing more: no plugins, no language servers.
- Employer config is the employer's marketplace, installed by its tooling; nothing here enables
  it.
- Secrets: `op://` references only, never a plaintext token, and nothing here prints one.
- The repo settings that are not files are `.github/gate.sh`, which the owner runs.
- A rule that can fail the build is a check in `mise.toml` or `.github/apply-check.sh`, and a
  rule an agent must obey is a setting; neither is a line here. History is the PRs.
