# dotFiles

A [chezmoi](https://www.chezmoi.io) source repo; there is no engine code. `home/` is the source
state (chezmoi's `dot_`/`private_` naming); everything else is repo plumbing. `chezmoi apply`
reconciles the machine, and `chezmoi verify` reports drift.

## Principles

North Star: **small, exemplary, easily shareable: a senior engineer's showpiece, not an
over-engineered personal artifact.** When a rule and a principle collide, surface the tradeoff.

- Native over special: deleting custom code for a built-in is the highest-value change.
- Guilty until proven load-bearing: every dependency, wrapper, and line earns its weight.
- One host, the Mac. A Claude Code web session is Linux and gets this repo, never `~`: lint and
  apply-check run there, and nothing applies. No by-hand step remains that `chezmoi apply` could
  converge. Upgrades are the nightly `mise run upkeep`; pins are the monthly Routine that runs
  `/bump` (`.claude/skills/bump`).
- Standard, and agentic-enabled: 1Password, git, ssh, `gh`, MCP stay stock, wired for agents.
- Keep it legible: one line on the decision, nothing on the mechanism.

## How a change lands

1. Work in a worktree of a clone (`~/Code/dotFiles` on the Mac).
2. Prove it with the `verify` skill: `mise run lint`, then `mise run apply-check`, which applies the
   source into a temporary home, so it is safe anywhere. Claude runs it before each commit.
3. Open a PR. `lint` is the one required check; CI runs the same two tasks on a Mac.
4. After it merges, `chezmoi update` applies it. chezmoi's own source is
   `~/.local/share/chezmoi`, and nothing else moves it.

Never apply a worktree to the real home directory. An agent's PR from a `claude/` branch merges
itself once `lint` passes (`agent-auto-merge.yml`). The floor is the exception: a PR that widens the
`permissions`, `sandbox`, `autoMode` or `env` blocks of
`home/.chezmoitemplates/claude-settings.json`, or makes a program run outside the sandbox (a
script, LaunchAgent, package, mise task, shell startup file, git key naming a program, the chezmoi
config, or `.github/gate.sh` and `main-green.sh`, which upkeep runs) lands only when the owner
asked for it. The workflow never switches those on, and lint bans templates that run a command.

## Local facts

- `home/dot_claude/` is the **user-global** Claude config (`~/.claude/`). The repo-root
  `.claude/` is this repo's project scope. Don't conflate them.
- `~/.claude/settings.json` is a modify template: chezmoi enforces the keys declared in
  `home/.chezmoitemplates/claude-settings.json` and leaves every other key to the app.
- Every runtime is a mise tool (`home/dot_config/mise/config.toml`), and every CLI a Brewfile
  formula, so its completions and man pages come with it; `1password-cli`, `gcloud-cli` and
  `ngrok` are casks. The Brewfile also holds the two zsh plugins and the apps. mise and the Claude
  Code CLI come from their own installers into `~/.local/bin`, and chezmoi's installer only
  bootstraps it: mise owns it from the first apply. git is the system's.
- `~/.local/bin` and `~/Library/LaunchAgents` are exact: apply deletes whatever they hold beyond
  what this repo declares and `.chezmoiignore` leaves to its owner.
- This repo's own linters are pinned in the root `mise.toml`, not installed machine-wide.
- `chezmoi apply` never upgrades anything; `mise run upkeep` does, nightly, and a failure opens an
  issue here, one per Mac and failing set of steps, closed by the next green run. It converges only
  a main whose `lint` passed on Actions; the nightly run then checks every owned repo against
  `gate.sh` and keeps one shared `gate:` issue. When the Brewfile changes, apply uninstalls every Homebrew package it
  does not name, and upkeep does the same nightly, on a Mac that said it is personal: `personal` is asked once at init (a terminal-less init passes
  `--promptBool "personal Mac=..."` or fails), and a work Mac keeps its employer's.
- Machine setup is `home/.chezmoiscripts/`. Homebrew and provisioning run on every apply behind a
  guard. mise, the launchd agents and the Brewfile re-run when their files
  change, and the macOS defaults when the script itself changes. Last, the extra Claude desktop
  apps re-run when `claudeProfiles` or Claude's icon changes; they go once Claude desktop holds
  several accounts itself.
- The macOS defaults are applied, not converged: `verify` runs no script and never sees them.
- `~/Code/.metadata_never_index` keeps Spotlight out of every repo; its indexer never settled
  under `~/Code`. Search code with `rg` and `fd`.
- One GitHub login: `gh auth login`, stored in the login keychain. Never `--insecure-storage`.
- Who this is (name, emails, signing key, GitHub user and orgs) lives in `home/.chezmoidata.toml`
  alone; repos in its work orgs commit as the work email.
- nvim is `$EDITOR` and nothing more: no plugins, no language servers.
- Employer config is the employer's marketplace, installed by its tooling; nothing here enables
  it.
- Secrets: `op://` references only, never a plaintext token, and nothing here prints one.
- The repo settings that are not files are `.github/gate.sh`, which the owner runs and upkeep
  checks read-only.
- A rule that can fail the build is a check in `mise.toml` or `.github/apply-check.sh`, and a
  rule an agent must obey is a setting; neither is a line here. History is the PRs.
