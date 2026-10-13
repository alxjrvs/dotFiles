# dotFiles

A [chezmoi](https://www.chezmoi.io) source repo for one Mac; there is no engine code. `home/` is
the source state (chezmoi's `dot_`/`private_` naming); everything else is repo plumbing.

Small and legible beats clever: native over custom, and every file earns its place. Comments say
why, never how.

## How a change lands

1. Work in a worktree of a clone (`~/Code/dotFiles` on the Mac), never chezmoi's own source.
2. Prove it with the `verify` skill before each commit. It applies into a temporary home, so it is
   safe anywhere, a cloud session included.
3. Open one PR. `lint` is the one required check. A `claude/` PR merges itself on green
   (`agent-auto-merge.yml`) unless it touches the floor: anything that runs outside the sandbox at
   apply or upkeep, the files that workflow's `floor` pattern names. Those land only when the owner
   asked for them.
4. After it merges, the owner runs `chezmoi update`; nothing applies main unattended. Never apply a
   worktree to the real home.

## Local facts

- `home/dot_claude/` is the **user-global** Claude config (`~/.claude/`); the repo-root `.claude/`
  is this repo's project scope. Don't conflate them.
- `~/.claude/settings.json` is a modify template: chezmoi enforces only the keys in
  `home/.chezmoitemplates/claude-settings.json`, and a `null` there retires a key.
- Runtimes are mise tools (`home/dot_config/mise/config.toml`), CLIs and apps are Brewfile entries,
  and this repo's own linters are pinned in the root `mise.toml`.
- Apply installs and never upgrades or uninstalls. The nightly `mise run upkeep` upgrades; a
  failure is a macOS notification pointing at `~/Library/Logs/upkeep.log`.
- Who this is (name, emails, signing key, GitHub user and orgs) lives in `home/.chezmoidata.toml`
  alone.
- Secrets: `op://` references through `op run`. Never a plaintext token, and nothing prints one.
