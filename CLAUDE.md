# dotFiles

A [chezmoi](https://www.chezmoi.io) source repo for a personal Mac, a work Mac and MAIA, a CachyOS
desktop; there is no engine code. `home/` is the source state (chezmoi's `dot_`/`private_` naming);
everything else is repo plumbing. `home/.chezmoiignore` decides what lands on which OS, and
`.mac` (personal or work, asked once at init) is where a difference between the Macs goes.

Small and legible beats clever: native over custom, and every file earns its place. Comments say
why, never how.

## Audits, cuts and reversals

- An audit ends in issues, one per finding, never in a PR of cuts.
- A cut states in its PR the evidence that the thing is unused: shell history, session history or
  a grep showing no caller.
- Decisions live in `docs/adr/` as short MADR files with a "Reopen when" section. A PR that
  reverses one names the ADR it changes and updates it.
- A commit subject states one change; a subject that needs commas is more than one PR.

## How a change lands

1. Work in a worktree of a clone (`~/Code/dotFiles` on the Mac), never chezmoi's own source.
2. Prove it with the `verify` skill before each commit. It applies into a temporary home, so it is
   safe anywhere, a cloud session included.
3. Open one PR. `lint` is the one required check. A `claude/` PR merges itself on green
   (`agent-auto-merge.yml`) only when every path it changes is on that workflow's short
   `allow` list. Everything else is the floor (what `chezmoi update`, upkeep, CI or a session
   may run) and lands only when the owner asked for it.
4. After it merges, the nightly upkeep runs `chezmoi update` when main's `lint` is green and no
   managed file was edited by hand; otherwise it skips, says why, and the owner runs it
   ([ADR 0002](docs/adr/0002-upkeep-applies-green-main.md)). Never apply a worktree to the real
   home.

## Local facts

- Claude Code's sandbox is on, on every machine. Why, what it lets through, and the evidence a
  reversal has to cite: `docs/adr/0001-claude-sandbox-on.md`.
- Runtimes are mise tools (`home/dot_config/mise/config.toml`), CLIs and apps are Brewfile entries
  on a Mac and `.chezmoiscripts/10-cachyos.sh` entries on CachyOS (keep the two in step), and this
  repo's own linters are pinned in the root `mise.toml`.
- Apply installs and never upgrades or uninstalls. The nightly `mise run upkeep` upgrades, then
  applies main; a failure, a skipped apply included, is a notification pointing at
  `~/Library/Logs/upkeep.log` (CachyOS: `~/.local/state/upkeep.log`).
- Who this is (name, emails, signing key, GitHub user and orgs) lives in `home/.chezmoidata.toml`
  alone.
- Secrets: `op://` references through `op run`. Never a plaintext token, and nothing prints one.
